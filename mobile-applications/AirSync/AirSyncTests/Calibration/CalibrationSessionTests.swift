import XCTest
@testable import AirSync

@MainActor
final class CalibrationSessionTests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Calibration session tests are skipped on the simulator to avoid audio hardware access.")
        #endif
    }

    func testCompletesCalibrationAndSubmitsResult() async {
        let config = TestAudioFixtures.defaultConfig
        let generator = ChirpGenerator(sampleRate: TestAudioFixtures.sampleRate)
        let detector = LatencyDetector(sampleRate: TestAudioFixtures.sampleRate)
        let recorded = TestAudioFixtures.recordedAudio(
            for: config,
            latencyMs: 45,
            noiseAmplitude: 0.05
        )

        let recorder = MockRecorder(samples: recorded, sampleRate: TestAudioFixtures.sampleRate)
        let api = MockCalibrationAPI()

        let session = CalibrationSession(
            generator: generator,
            detector: detector,
            recorder: recorder,
            api: api,
            config: config,
            microphoneAccess: {}
        )

        await session.start()

        guard case let .completed(measurement) = session.stage else {
            return XCTFail("Expected completed stage, got \(session.stage)")
        }

        XCTAssertEqual(measurement.latencyMs, 45, accuracy: 7)
        XCTAssertEqual(api.startRequests, 1)
        XCTAssertEqual(api.lastDelayMs, 800)
        XCTAssertNotNil(api.submittedResult)
        XCTAssertEqual(api.submittedResult?.latencyMs ?? 0, measurement.latencyMs, accuracy: 7)
        XCTAssertGreaterThan(api.submittedResult?.confidence ?? 0, 0.3)
    }

    func testSurfaceFailureWhenRecorderThrows() async {
        let config = TestAudioFixtures.defaultConfig
        let api = MockCalibrationAPI()
        let recorder = FailingRecorder()

        let session = CalibrationSession(
            recorder: recorder,
            api: api,
            config: config,
            microphoneAccess: {}
        )

        await session.start()

        if case .failed = session.stage {
            XCTAssertEqual(api.startRequests, 1)
            XCTAssertEqual(api.lastDelayMs, 800)
        } else {
            XCTFail("Expected failure stage")
        }
    }
}

private final class MockRecorder: MicrophoneRecorder {
    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    func record(for duration: TimeInterval, sampleRate: Double) async throws -> [Float] {
        XCTAssertEqual(sampleRate, self.sampleRate, accuracy: 0.1)
        return samples
    }
}

private final class FailingRecorder: MicrophoneRecorder {
    func record(for duration: TimeInterval, sampleRate: Double) async throws -> [Float] {
        throw NSError(domain: "Recorder", code: -1)
    }
}

private final class MockCalibrationAPI: CalibrationAPI {
    private(set) var startRequests = 0
    private(set) var submittedResult: CalibrationResultPayload?
    private(set) var lastDelayMs: UInt64?

    func startPlayback(_ config: ChirpConfig, delayMs: UInt64) async throws {
        startRequests += 1
        lastDelayMs = delayMs
    }

    func submitResult(_ result: CalibrationResultPayload) async throws {
        submittedResult = result
    }
}
