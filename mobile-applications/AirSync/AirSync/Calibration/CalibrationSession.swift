import AVFoundation
import Accelerate
import Combine
import Foundation

struct CalibrationResultPayload: Codable, Equatable {
    let timestamp: UInt64
    let latencyMs: Double
    let confidence: Double
    let detections: [DetectionPayload]

    enum CodingKeys: String, CodingKey {
        case timestamp
        case latencyMs = "latency_ms"
        case confidence
        case detections
    }
}

struct DetectionPayload: Codable, Equatable {
    let markerId: String?
    let sampleIndex: Int
    let correlation: Double
    let latencyMs: Double?

    enum CodingKeys: String, CodingKey {
        case markerId = "marker_id"
        case sampleIndex = "sample_index"
        case correlation
        case latencyMs = "latency_ms"
    }
}

struct CalibrationRequestPayload: Codable {
    let timestamp: UInt64
    let chirpConfig: ChirpConfig
    let delayMs: UInt64
    let structured: Bool

    enum CodingKeys: String, CodingKey {
        case timestamp
        case chirpConfig = "chirp_config"
        case delayMs = "delay_ms"
        case structured
    }
}

protocol CalibrationAPI {
    func serverTimeMs() async throws -> UInt64
    func startPlayback(_ config: ChirpConfig, delayMs: UInt64, structured: Bool) async throws
    func triggerPlayback(targetStartMs: UInt64) async throws
    func submitResult(_ result: CalibrationResultPayload) async throws
    func fetchCalibrationSpec() async throws -> CalibrationSignalSpec
}

protocol MicrophoneRecorder {
    func record(
        for duration: TimeInterval,
        sampleRate: Double,
        levelHandler: @escaping (Float) -> Void
    ) async throws -> RecordedAudio
}

struct RecordedAudio {
    let samples: [Float]
    let startedAtMs: UInt64
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
    @Published private(set) var calculationProgress: Double = 0
    @Published private(set) var micPulse: Bool = false
    @Published private(set) var frequencyRange: (Double, Double)?

    private let generator: ChirpGenerator
    private let detector: LatencyDetector
    private let recorder: MicrophoneRecorder
    private let api: CalibrationAPI
    private var config: ChirpConfig
    private let microphoneAccess: () async throws -> Void
    private var progressTask: Task<Void, Never>?
    private var calcProgressTask: Task<Void, Never>?
    private var expectedDuration: TimeInterval = 1.0
    private let playbackDelayMs: UInt64 = 3_000
    private let detectorSlackMs: Double = 600

    init(
        generator: ChirpGenerator? = nil,
        detector: LatencyDetector? = nil,
        recorder: MicrophoneRecorder,
        api: CalibrationAPI,
        config: ChirpConfig = .defaultConfig,
        microphoneAccess: @escaping () async throws -> Void = CalibrationSession.requestMicrophoneAccess
    ) {
        self.generator = generator ?? ChirpGenerator()
        let maxLatencyMs = detectorSlackMs
        self.detector = detector ?? LatencyDetector(maximumLatencyMs: maxLatencyMs)
        self.recorder = recorder
        self.api = api
        self.config = config
        self.microphoneAccess = microphoneAccess
    }

    func start() async {
        progressTask?.cancel()
        calcProgressTask?.cancel()
        progress = 0
        calculationProgress = 0
        stage = .requestingPlayback
        var recordingTask: Task<RecordedAudio, Error>?
        do {
            try await microphoneAccess()
            print("Calibration starting with config: start=\(config.startFrequency)Hz end=\(config.endFrequency)Hz durationMs=\(config.durationMs) reps=\(config.repetitions) intervalMs=\(config.intervalMs) amp=\(config.amplitude)")

            let offset = await estimateServerOffsetMs() ?? 0

            // Structured-only: require spec and request structured playback
            let spec = try await api.fetchCalibrationSpec()
            let sampleRate = Double(spec.sampleRate)
            frequencyRange = Self.frequencyRange(from: spec)

            try await api.startPlayback(config, delayMs: playbackDelayMs, structured: true)
            let delaySeconds = Double(playbackDelayMs) / 1_000
            let lengthSeconds = Double(spec.lengthSamples) / Double(spec.sampleRate)
            let recordDuration: TimeInterval = delaySeconds + lengthSeconds + 1.0
            let total = recordDuration + 0.5
            expectedDuration = total
            startProgressTimer(totalDuration: total)

            stage = .recording
            let clientNowMs = Self.timestampNow()
            let serverNow = Double(clientNowMs) + offset
            let targetStart = UInt64(serverNow) + playbackDelayMs + 1_000 // safety cushion
            print("Calibration target start (server ms): \(targetStart) offset_ms=\(offset)")

            recordingTask = Task {
                print("Calibration recording started for \(recordDuration)s at sampleRate \(sampleRate)Hz")
                return try await recorder.record(
                    for: recordDuration,
                    sampleRate: sampleRate,
                    levelHandler: { [weak self] rms in
                        guard let self else { return }
                        self.handleMicLevel(rms)
                    }
                )
            }
            try await api.triggerPlayback(targetStartMs: targetStart)
            let recording = try await recordingTask?.value ?? RecordedAudio(samples: [], startedAtMs: Self.timestampNow())
            let rms = Self.rms(recording.samples)
            let peak = recording.samples.map { abs($0) }.max() ?? 0
            let nonZero = recording.samples.filter { $0 != 0 }.count
            print("Calibration recording finished, samples captured: \(recording.samples.count) nonZero=\(nonZero) rms=\(rms) peak=\(peak) started_at_ms=\(recording.startedAtMs)")

            stage = .calculating
            startCalculationProgressTimer(totalDuration: 6)
            print("Calibration measuring latency...")
            let expectedStartClientMs = Double(targetStart) - offset
            let leadMs = max(0, expectedStartClientMs - Double(recording.startedAtMs))
            let startOffsetSamples = max(0, Int((leadMs / 1000.0) * sampleRate))
            print("Calibration alignment: lead_ms=\(leadMs) start_offset_samples=\(startOffsetSamples)")

            let measurement: LatencyMeasurement
            let detector = StructuredDetector(sampleRate: Double(spec.sampleRate))
            measurement = detector.measure(
                recording: recording.samples,
                spec: spec,
                startOffsetSamples: startOffsetSamples
            )
            let detectionCount = measurement.detections.count
            let topDetection = measurement.detections.max(by: { $0.correlation < $1.correlation })
            print(
                "Calibration measurement lat_ms=\(measurement.latencyMs) conf=\(measurement.confidence) detections=\(detectionCount) top_corr=\(topDetection?.correlation ?? 0) top_sample_idx=\(topDetection?.sampleIndex ?? 0)"
            )
            latestMeasurement = measurement
            calcProgressTask?.cancel()
            calculationProgress = 1

            if detectionCount == 0 {
                print("Calibration detected zero markers; submitting zero-confidence result for visibility.")
            }

            stage = .sending
            let payload = CalibrationResultPayload(
                timestamp: Self.timestampNow(),
                latencyMs: measurement.latencyMs,
                confidence: measurement.confidence,
                detections: measurement.detections.map {
                    DetectionPayload(
                        markerId: $0.markerId,
                        sampleIndex: $0.sampleIndex,
                        correlation: $0.correlation,
                        latencyMs: $0.latencyMs
                    )
                }
            )

            try await api.submitResult(payload)
            stage = .completed(measurement)
            progress = 1
            calculationProgress = 1
        } catch {
            print("Calibration failed: \(error.localizedDescription)")
            stage = .failed(error.localizedDescription)
            progressTask?.cancel()
            calcProgressTask?.cancel()
            progress = 0
            calculationProgress = 0
            recordingTask?.cancel()
        }
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }

    func setAmplitude(_ value: Double) {
        config = ChirpConfig(
            startFrequency: config.startFrequency,
            endFrequency: config.endFrequency,
            durationMs: config.durationMs,
            repetitions: config.repetitions,
            intervalMs: config.intervalMs,
            amplitude: max(0.0, min(1.0, value))
        )
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
        return chirpDuration + detector.searchWindowSeconds + 0.5
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

    private func startCalculationProgressTimer(totalDuration: TimeInterval) {
        calcProgressTask?.cancel()
        let start = Date()
        calcProgressTask = Task { [weak self] in
            while let self = self, !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let fraction = min(1.0, elapsed / totalDuration)
                await MainActor.run {
                    self.calculationProgress = fraction
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
                if fraction >= 1.0 || self.stage.isTerminal || self.stage == .sending {
                    break
                }
            }
        }
    }

    private static func timestampNow() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    private func estimateServerOffsetMs() async -> Double? {
        var offsets: [Double] = []
        for _ in 0..<2 {
            let t0 = Self.timestampNow()
            guard let server = try? await api.serverTimeMs() else { continue }
            let t2 = Self.timestampNow()
            let avgClient = Double(t0 + t2) / 2.0
            let offset = Double(server) - avgClient
            offsets.append(offset)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard !offsets.isEmpty else { return nil }
        let sorted = offsets.sorted()
        let mid = sorted.count / 2
        let median = sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2.0 : sorted[mid]
        return median
    }

    private func handleMicLevel(_ rms: Float) {
        let threshold: Float = 0.02
        guard rms > threshold else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if micPulse { return }
            micPulse = true
            try? await Task.sleep(nanoseconds: 150_000_000)
            micPulse = false
        }
    }

    private static func frequencyRange(from spec: CalibrationSignalSpec) -> (Double, Double)? {
        let freqs = spec.markers.compactMap { marker -> Double? in
            switch marker.kind {
            case .click:
                return nil
            case let .chirp(startFreq, endFreq, _):
                return Double(min(startFreq, endFreq))
            }
        }
        guard let min = freqs.min(), let max = freqs.max() else { return nil }
        return (min, max)
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

extension CalibrationSession {
    func applyLatestMeasurement() async {
        guard let measurement = latestMeasurement else { return }
        stage = .sending
        do {
            let payload = CalibrationResultPayload(
                timestamp: Self.timestampNow(),
                latencyMs: measurement.latencyMs,
                confidence: measurement.confidence,
                detections: measurement.detections.map {
                    DetectionPayload(
                        markerId: $0.markerId,
                        sampleIndex: $0.sampleIndex,
                        correlation: $0.correlation,
                        latencyMs: $0.latencyMs
                    )
                }
            )
            try await api.submitResult(payload)
            stage = .completed(measurement)
        } catch {
            print("Apply latest failed: \(error.localizedDescription)")
            stage = .failed(error.localizedDescription)
        }
    }
}

private struct SilentRecorder: MicrophoneRecorder {
    func record(
        for duration: TimeInterval,
        sampleRate: Double,
        levelHandler: @escaping (Float) -> Void
    ) async throws -> RecordedAudio {
        let frameCount = Int((duration * sampleRate).rounded(.up))
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1_000)
        return RecordedAudio(samples: Array(repeating: 0, count: frameCount), startedAtMs: nowMs)
    }
}

private struct NoopCalibrationAPI: CalibrationAPI {
    func serverTimeMs() async throws -> UInt64 { 0 }
    func startPlayback(_ config: ChirpConfig, delayMs: UInt64, structured: Bool) async throws {}
    func triggerPlayback(targetStartMs: UInt64) async throws {}
    func submitResult(_ result: CalibrationResultPayload) async throws {}
    func fetchCalibrationSpec() async throws -> CalibrationSignalSpec {
        throw URLError(.badURL)
    }
}

final class AVMicrophoneRecorder: MicrophoneRecorder {
    func record(
        for duration: TimeInterval,
        sampleRate: Double,
        levelHandler: @escaping (Float) -> Void
    ) async throws -> RecordedAudio {
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
            options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]
        )
        try AVAudioSession.sharedInstance().setMode(.measurement)
        try AVAudioSession.sharedInstance().setPreferredSampleRate(sampleRate)
        try AVAudioSession.sharedInstance().setActive(true, options: [])

        var collected: [Float] = []
        var startedAtMs: UInt64?
        let targetFrames = Int((duration * sampleRate).rounded(.up))

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false

            func finish(_ result: Result<RecordedAudio, Error>) {
                guard !finished else { return }
                finished = true
                input.removeTap(onBus: 0)
                engine.stop()

                switch result {
                case let .success(audio):
                    continuation.resume(returning: audio)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                guard let channelData = buffer.floatChannelData else { return }
                let frameLength = Int(buffer.frameLength)
                let pointer = UnsafeBufferPointer(start: channelData[0], count: frameLength)
                collected.append(contentsOf: pointer)
                if startedAtMs == nil {
                    startedAtMs = UInt64(Date().timeIntervalSince1970 * 1_000)
                }
                levelHandler(Self.bufferRMS(pointer))

                if collected.count >= targetFrames {
                    let trimmed = Array(collected.prefix(targetFrames))
                    let nowMs = UInt64(Date().timeIntervalSince1970 * 1_000)
                    finish(.success(RecordedAudio(samples: trimmed, startedAtMs: startedAtMs ?? nowMs)))
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
                let nowMs = UInt64(Date().timeIntervalSince1970 * 1_000)
                finish(.success(RecordedAudio(samples: trimmed, startedAtMs: startedAtMs ?? nowMs)))
            }
        }
    }

    private static func bufferRMS(_ buffer: UnsafeBufferPointer<Float>) -> Float {
        guard !buffer.isEmpty else { return 0 }
        var meanSquare: Float = 0
        vDSP_measqv(buffer.baseAddress!, 1, &meanSquare, vDSP_Length(buffer.count))
        return sqrt(meanSquare)
    }
}
