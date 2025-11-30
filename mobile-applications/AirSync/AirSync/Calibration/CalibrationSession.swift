import AVFoundation
import Combine
import Foundation

struct CalibrationResultPayload: Codable, Equatable {
    let timestamp: UInt64
    let latencyMs: Double
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case timestamp
        case latencyMs = "latency_ms"
        case confidence
    }
}

struct CalibrationRequestPayload: Codable {
    let timestamp: UInt64
    let chirpConfig: ChirpConfig
    let delayMs: UInt64

    enum CodingKeys: String, CodingKey {
        case timestamp
        case chirpConfig = "chirp_config"
        case delayMs = "delay_ms"
    }
}

protocol CalibrationAPI {
    func startPlayback(_ config: ChirpConfig, delayMs: UInt64) async throws
    func submitResult(_ result: CalibrationResultPayload) async throws
}

protocol MicrophoneRecorder {
    func record(for duration: TimeInterval, sampleRate: Double) async throws -> [Float]
}

enum CalibrationStage: Equatable {
    case idle
    case requestingPlayback
    case recording
    case calculating
    case sending
    case completed(LatencyMeasurement)
    case failed(String)

    static func == (lhs: CalibrationStage, rhs: CalibrationStage) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.requestingPlayback, .requestingPlayback), (.recording, .recording),
             (.calculating, .calculating), (.sending, .sending):
            return true
        case let (.completed(a), .completed(b)):
            return a == b
        case let (.failed(a), .failed(b)):
            return a == b
        default:
            return false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum CalibrationError: LocalizedError {
    case microphoneAccessDenied

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access is required for calibration."
        }
    }
}

@MainActor
final class CalibrationSession: ObservableObject {
    @Published private(set) var stage: CalibrationStage = .idle
    @Published private(set) var latestMeasurement: LatencyMeasurement?
    @Published private(set) var progress: Double = 0

    private let generator: ChirpGenerator
    private let detector: LatencyDetector
    private let recorder: MicrophoneRecorder
    private let api: CalibrationAPI
    private let config: ChirpConfig
    private let microphoneAccess: () async throws -> Void
    private var progressTask: Task<Void, Never>?
    private var expectedDuration: TimeInterval = 1.0
    private let playbackDelayMs: UInt64 = 800

    init(
        generator: ChirpGenerator? = nil,
        detector: LatencyDetector? = nil,
        recorder: MicrophoneRecorder,
        api: CalibrationAPI,
        config: ChirpConfig = .defaultConfig,
        microphoneAccess: @escaping () async throws -> Void = CalibrationSession.requestMicrophoneAccess
    ) {
        self.generator = generator ?? ChirpGenerator()
        self.detector = detector ?? LatencyDetector()
        self.recorder = recorder
        self.api = api
        self.config = config
        self.microphoneAccess = microphoneAccess
    }

    func start() async {
        progressTask?.cancel()
        progress = 0
        stage = .requestingPlayback
        do {
            try await microphoneAccess()
            let sequence = generator.makeSequence(config: config)
            try await api.startPlayback(config, delayMs: playbackDelayMs)
            let total = recordingDuration(for: sequence) + 0.5
            expectedDuration = total
            startProgressTimer(totalDuration: total)

            stage = .recording
            let recording = try await recorder.record(
                for: recordingDuration(for: sequence),
                sampleRate: sequence.sampleRate
            )

            stage = .calculating
            let measurement = detector.measure(recording: recording, sequence: sequence)
            latestMeasurement = measurement

            stage = .sending
            let payload = CalibrationResultPayload(
                timestamp: Self.timestampNow(),
                latencyMs: measurement.latencyMs,
                confidence: measurement.confidence
            )

            try await api.submitResult(payload)
            stage = .completed(measurement)
            progress = 1
        } catch {
            stage = .failed(error.localizedDescription)
            progressTask?.cancel()
            progress = 0
        }
    }

    private static func requestMicrophoneAccess() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }

        if !granted {
            throw CalibrationError.microphoneAccessDenied
        }
    }

    private func recordingDuration(for sequence: ChirpSequence) -> TimeInterval {
        let chirpDuration = Double(sequence.samples.count) / sequence.sampleRate
        return chirpDuration + detector.searchWindowSeconds + 0.05
    }

    private func startProgressTimer(totalDuration: TimeInterval) {
        progressTask?.cancel()
        let start = Date()
        progressTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let fraction = min(1.0, elapsed / totalDuration)
                await MainActor.run {
                    self.progress = fraction
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                if fraction >= 1.0 || self.stage.isTerminal {
                    break
                }
            }
        }
    }

    private static func timestampNow() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}

extension CalibrationSession {
    static func liveReceiverSession(
        baseURL: URL = URL(string: "http://raspberrypi.local:5000")!
    ) -> CalibrationSession {
        CalibrationSession(
            recorder: AVMicrophoneRecorder(),
            api: ReceiverCalibrationClient(baseURL: baseURL)
        )
    }

    static func previewSession(measurement: LatencyMeasurement? = nil) -> CalibrationSession {
        let session = CalibrationSession(
            generator: ChirpGenerator(),
            detector: LatencyDetector(),
            recorder: SilentRecorder(),
            api: NoopCalibrationAPI(),
            microphoneAccess: {}
        )

        if let measurement {
            session.latestMeasurement = measurement
        }

        return session
    }
}

private struct SilentRecorder: MicrophoneRecorder {
    func record(for duration: TimeInterval, sampleRate: Double) async throws -> [Float] {
        let frameCount = Int((duration * sampleRate).rounded(.up))
        return Array(repeating: 0, count: frameCount)
    }
}

private struct NoopCalibrationAPI: CalibrationAPI {
    func startPlayback(_ config: ChirpConfig, delayMs: UInt64) async throws {}
    func submitResult(_ result: CalibrationResultPayload) async throws {}
}

final class AVMicrophoneRecorder: MicrophoneRecorder {
    func record(for duration: TimeInterval, sampleRate: Double) async throws -> [Float] {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try AVAudioSession.sharedInstance().setPreferredSampleRate(sampleRate)
        try AVAudioSession.sharedInstance().setActive(true, options: [])

        var collected: [Float] = []
        let targetFrames = Int((duration * sampleRate).rounded(.up))

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false

            func finish(_ result: Result<[Float], Error>) {
                guard !finished else { return }
                finished = true
                input.removeTap(onBus: 0)
                engine.stop()

                switch result {
                case let .success(samples):
                    continuation.resume(returning: samples)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                let pointer = UnsafeBufferPointer(start: channelData[0], count: frameLength)
                collected.append(contentsOf: pointer)

                if collected.count >= targetFrames {
                    let trimmed = Array(collected.prefix(targetFrames))
                    finish(.success(trimmed))
                }
            }

            do {
                try engine.start()
            } catch {
                finish(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.1) * 1_000_000_000))
                let trimmed = Array(collected.prefix(min(collected.count, targetFrames)))
                finish(.success(trimmed))
            }
        }
    }
}
