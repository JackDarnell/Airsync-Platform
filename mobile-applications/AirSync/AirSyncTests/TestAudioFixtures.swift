import Foundation
@testable import AirSync

enum TestAudioFixtures {
    static let sampleRate: Double = 48_000
    static let defaultConfig = ChirpConfig(
        startFrequency: 2_000,
        endFrequency: 8_000,
        durationMs: 50,
        repetitions: 5,
        intervalMs: 500
    )

    static func referenceSequence(config: ChirpConfig = defaultConfig) -> ChirpSequence {
        let generator = ChirpGenerator(sampleRate: sampleRate)
        return generator.makeSequence(config: config)
    }

    static func recordedAudio(
        for config: ChirpConfig = defaultConfig,
        latencyMs: Double,
        noiseAmplitude: Float = 0.0
    ) -> [Float] {
        let sequence = referenceSequence(config: config)
        let latencySamples = Int(sampleRate * latencyMs / 1_000)
        var recording = Array(repeating: Float(0), count: latencySamples + sequence.samples.count)

        for (index, sample) in sequence.samples.enumerated() {
            recording[latencySamples + index] = sample
        }

        if noiseAmplitude > 0 {
            var generator = SeededRandom()
            for index in recording.indices {
                let noise = Float.random(in: -noiseAmplitude...noiseAmplitude, using: &generator)
                recording[index] += noise
            }
        }

        return recording
    }

    static func detector() -> LatencyDetector {
        LatencyDetector(sampleRate: sampleRate)
    }
}

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64 = 0xCAFE_F00D

    mutating func next() -> UInt64 {
        state = state &* 636_413_622_384_679_3005 &+ 1
        return state
    }
}
