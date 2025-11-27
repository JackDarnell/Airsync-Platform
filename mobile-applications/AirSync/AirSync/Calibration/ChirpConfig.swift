//
//  ChirpConfig.swift
//  AirSync
//

import Foundation

struct ChirpConfig: Equatable {
    let startFrequency: Double
    let endFrequency: Double
    let durationMs: Double
    let repetitions: Int
    let intervalMs: Double

    static var defaultConfig: ChirpConfig {
        ChirpConfig(
            startFrequency: 2_000,
            endFrequency: 8_000,
            durationMs: 50,
            repetitions: 5,
            intervalMs: 500
        )
    }
}
