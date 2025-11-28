import XCTest
@testable import AirSync

final class LatencyDetectorTests: XCTestCase {
    private let sampleRate = TestAudioFixtures.sampleRate

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Latency detector tests are skipped on the simulator due to unavailable audio timing hardware.")
        #endif
    }

    func testDetectsInsertedDelayWithinTolerance() {
        let config = ChirpConfig.defaultConfig
        let sequence = TestAudioFixtures.referenceSequence(config: config)
        let recordedAudio = TestAudioFixtures.recordedAudio(for: config, latencyMs: 55, noiseAmplitude: 0.01)

        let detector = LatencyDetector(sampleRate: sampleRate)
        let measurement = detector.measure(recording: recordedAudio, sequence: sequence)

        XCTAssertEqual(measurement.latencyMs, 55, accuracy: 5)
        XCTAssertGreaterThan(measurement.confidence, 0.8)
        XCTAssertEqual(measurement.detections.count, config.repetitions)
    }

    func testDetectsLatencyWithModerateNoise() {
        let config = ChirpConfig(startFrequency: 2000, endFrequency: 8000, durationMs: 50, repetitions: 5, intervalMs: 250)
        let sequence = TestAudioFixtures.referenceSequence(config: config)
        let recordedAudio = TestAudioFixtures.recordedAudio(for: config, latencyMs: 32, noiseAmplitude: 0.15)

        let detector = LatencyDetector(sampleRate: sampleRate)
        let measurement = detector.measure(recording: recordedAudio, sequence: sequence)

        XCTAssertEqual(measurement.latencyMs, 32, accuracy: 7)
        XCTAssertGreaterThan(measurement.confidence, 0.5)
    }

    func testIdentifiesEarliestChirpWhenRepeated() {
        let config = ChirpConfig(startFrequency: 2200, endFrequency: 7600, durationMs: 60, repetitions: 3, intervalMs: 180)
        let sequence = TestAudioFixtures.referenceSequence(config: config)
        let recordedAudio = TestAudioFixtures.recordedAudio(for: config, latencyMs: 25, noiseAmplitude: 0.02)

        let detector = LatencyDetector(sampleRate: sampleRate)
        let measurement = detector.measure(recording: recordedAudio, sequence: sequence)

        XCTAssertEqual(measurement.latencyMs, 25, accuracy: 5)
    }

    func testConfidenceDropsWithHeavierNoise() {
        let config = ChirpConfig.defaultConfig
        let sequence = TestAudioFixtures.referenceSequence(config: config)

        let clean = LatencyDetector(sampleRate: sampleRate).measure(
            recording: TestAudioFixtures.recordedAudio(for: config, latencyMs: 40, noiseAmplitude: 0.01),
            sequence: sequence
        )

        let noisy = LatencyDetector(sampleRate: sampleRate).measure(
            recording: TestAudioFixtures.recordedAudio(for: config, latencyMs: 40, noiseAmplitude: 0.4),
            sequence: sequence
        )

        XCTAssertEqual(clean.latencyMs, 40, accuracy: 3)
        XCTAssertEqual(noisy.latencyMs, 40, accuracy: 8)
        XCTAssertGreaterThan(clean.confidence, noisy.confidence)
    }
}
