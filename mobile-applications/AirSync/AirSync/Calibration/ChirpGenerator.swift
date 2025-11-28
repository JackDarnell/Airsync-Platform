//
//  ChirpGenerator.swift
//  AirSync
//

import Foundation

struct ChirpGenerator {
    let sampleRate: Double

    init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
    }

    func makeSequence(config: ChirpConfig) -> ChirpSequence {
        let reference = makeReference(config: config)
        let chirpSamples = reference.count
        let gapSamples = Int(sampleRate * config.intervalMs / 1_000)
        let stride = chirpSamples + gapSamples
        var samples: [Float] = []
        samples.reserveCapacity(config.repetitions * stride)

        for index in 0..<config.repetitions {
            samples.append(contentsOf: reference)
            if index < config.repetitions - 1 {
                samples.append(contentsOf: Array(repeating: Float(0), count: gapSamples))
            }
        }

        return ChirpSequence(
            samples: samples,
            referenceChirp: reference,
            chirpSamples: chirpSamples,
            gapSamples: gapSamples,
            sampleRate: sampleRate,
            config: config
        )
    }

    func makeReference(config: ChirpConfig) -> [Float] {
        let chirpSamples = max(1, Int(sampleRate * config.durationMs / 1_000))
        let durationSeconds = config.durationMs / 1_000

        return (0..<chirpSamples).map { index in
            let time = Double(index) / sampleRate
            let progress = durationSeconds == 0 ? 0 : time / durationSeconds
            let frequency = config.startFrequency + (config.endFrequency - config.startFrequency) * progress
            let rawSample = sin(2 * .pi * frequency * time)
            let denominator = Double(max(1, chirpSamples - 1))
            let window = 0.5 * (1 - cos(2 * .pi * Double(index) / denominator))
            return Float(rawSample * window)
        }
    }
}
