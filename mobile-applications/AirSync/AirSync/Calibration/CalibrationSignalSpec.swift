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
        // Accept either `"click"`/`"chirp"` strings or nested objects as sent by the receiver (serde untagged).
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
            switch value {
            case "click":
                self = .click
                return
            case "chirp":
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Chirp requires parameters"))
            default:
                break
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.click) {
            self = .click
            return
        }

        // serde represents the chirp variant as { "chirp": { "start_freq": ..., ... } }
        if container.contains(.chirp) {
            let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .chirp)
            let start = try nested.decode(UInt32.self, forKey: .startFreq)
            let end = try nested.decode(UInt32.self, forKey: .endFreq)
            let dur = try nested.decode(UInt32.self, forKey: .durationMs)
            self = .chirp(startFreq: start, endFreq: end, durationMs: dur)
            return
        }

        if container.contains(.startFreq) {
            let start = try container.decode(UInt32.self, forKey: .startFreq)
            let end = try container.decode(UInt32.self, forKey: .endFreq)
            let dur = try container.decode(UInt32.self, forKey: .durationMs)
            self = .chirp(startFreq: start, endFreq: end, durationMs: dur)
            return
        }

        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown marker kind"))
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
