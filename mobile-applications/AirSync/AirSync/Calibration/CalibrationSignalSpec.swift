import Foundation

enum MarkerKind: Decodable, Equatable {
    case click
    case chirp(startFreq: UInt32, endFreq: UInt32, durationMs: UInt32)

    private enum CodingKeys: String, CodingKey {
        case click
        case chirp
        case startFreq = "start_freq"
        case endFreq = "end_freq"
        case durationMs = "duration_ms"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.click) {
            self = .click
        } else if container.contains(.chirp) || container.contains(.startFreq) {
            let start = try container.decode(UInt32.self, forKey: .startFreq)
            let end = try container.decode(UInt32.self, forKey: .endFreq)
            let dur = try container.decode(UInt32.self, forKey: .durationMs)
            self = .chirp(startFreq: start, endFreq: end, durationMs: dur)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown marker kind"))
        }
    }
}

struct MarkerSpec: Decodable, Equatable {
    let id: String
    let kind: MarkerKind
    let startSample: UInt32
    let durationSamples: UInt32

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case startSample = "start_sample"
        case durationSamples = "duration_samples"
    }
}

struct CalibrationSignalSpec: Decodable, Equatable {
    let sampleRate: UInt32
    let lengthSamples: UInt32
    let markers: [MarkerSpec]

    private enum CodingKeys: String, CodingKey {
        case sampleRate = "sample_rate"
        case lengthSamples = "length_samples"
        case markers
    }
}
