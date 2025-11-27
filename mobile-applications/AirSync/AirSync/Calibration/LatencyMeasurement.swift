import Foundation

struct LatencyDetection: Equatable {
    let latencyMs: Double
    let correlation: Double
    let sampleIndex: Int
}

struct LatencyMeasurement: Equatable {
    let latencyMs: Double
    let confidence: Double
    let detections: [LatencyDetection]
}
