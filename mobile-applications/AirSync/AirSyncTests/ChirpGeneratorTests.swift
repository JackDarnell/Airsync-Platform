//
//  ChirpGeneratorTests.swift
//  AirSyncTests
//

import XCTest
@testable import AirSync

final class ChirpGeneratorTests: XCTestCase {
    func testSequenceMatchesConfig() {
        let config = TestAudioFixtures.defaultConfig
        let sequence = TestAudioFixtures.referenceSequence()

        let chirpSamples = Int(TestAudioFixtures.sampleRate * config.durationMs / 1_000)
        let gapSamples = Int(TestAudioFixtures.sampleRate * config.intervalMs / 1_000)
        let expectedTotal = config.repetitions * chirpSamples + (config.repetitions - 1) * gapSamples
        let expectedStarts = (0..<config.repetitions).map { $0 * (chirpSamples + gapSamples) }

        XCTAssertEqual(sequence.samples.count, expectedTotal)
        XCTAssertEqual(sequence.expectedStartSamples, expectedStarts)
    }

    func testChirpIsWindowed() {
        let sequence = TestAudioFixtures.referenceSequence()
        let chirpSamples = Int(TestAudioFixtures.sampleRate * TestAudioFixtures.defaultConfig.durationMs / 1_000)

        let firstSample = sequence.samples[0]
        let lastSampleOfFirstChirp = sequence.samples[chirpSamples - 1]

        XCTAssertLessThan(abs(firstSample), 0.01)
        XCTAssertLessThan(abs(lastSampleOfFirstChirp), 0.01)
    }
}
