import Foundation

struct ChirpSequence: Equatable {
    let samples: [Float]
    let referenceChirp: [Float]
    let chirpSamples: Int
    let gapSamples: Int
    let sampleRate: Double
    let config: ChirpConfig

    var expectedStartSamples: [Int] {
        let stride = chirpSamples + gapSamples
        return (0..<config.repetitions).map { $0 * stride }
    }
}
