//
//  ChirpConfig.swift
//  AirSync
//

import Foundation

struct ChirpConfig: Equatable, Codable {
    let startFrequency: Double
    let endFrequency: Double
    let durationMs: Double
    let repetitions: Int
    let intervalMs: Double

    static var defaultConfig: ChirpConfig {
        ChirpConfig(
            startFrequency: 1_000,
            endFrequency: 10_000,
            durationMs: 100,
            repetitions: 6,
            intervalMs: 400
        )
    }

    enum CodingKeys: String, CodingKey {
        case startFrequency = "start_freq"
        case endFrequency = "end_freq"
        case durationMs = "duration"
        case repetitions
        case intervalMs = "interval_ms"
    }
}
