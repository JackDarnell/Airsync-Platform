//
//  LatencyDetector.swift
//  AirSync
//

import Accelerate
import Foundation

final class LatencyDetector {
    private let sampleRate: Double
    private let maximumLatencyMs: Double

    init(sampleRate: Double = 48_000, maximumLatencyMs: Double = 250) {
        self.sampleRate = sampleRate
        self.maximumLatencyMs = maximumLatencyMs
    }

    var searchWindowMs: Double { maximumLatencyMs }
    var searchWindowSeconds: Double { maximumLatencyMs / 1_000 }

    func measure(recording: [Float], sequence: ChirpSequence) -> LatencyMeasurement {
        guard !recording.isEmpty, !sequence.referenceChirp.isEmpty else {
            return LatencyMeasurement(latencyMs: 0, confidence: 0, detections: [])
        }

        let normalizedRecording = normalize(recording)
        let normalizedReference = normalize(sequence.referenceChirp)
        let maxLatencySamples = Int(sampleRate * maximumLatencyMs / 1_000)

        var detections: [LatencyDetection] = []

        for expectedStart in sequence.expectedStartSamples {
            guard let detection = findBestAlignment(
                expectedStart: expectedStart,
                recording: normalizedRecording,
                reference: normalizedReference,
                maxOffset: maxLatencySamples
            ) else { continue }

            detections.append(
                LatencyDetection(
                    latencyMs: detection.latencyMs,
                    correlation: detection.correlation,
                    sampleIndex: detection.sampleIndex
                )
            )
        }

        let averageLatency = detections.map(\.latencyMs).average ?? 0
        let rawConfidence = detections.map(\.correlation).average ?? 0
        let confidence = rawConfidence.clamped(to: 0...1)

        return LatencyMeasurement(latencyMs: averageLatency, confidence: confidence, detections: detections)
    }

    private func findBestAlignment(
        expectedStart: Int,
        recording: [Float],
        reference: [Float],
        maxOffset: Int
    ) -> LatencyDetection? {
        let length = reference.count
        let lowerBound = max(0, expectedStart - maxOffset)
        let upperBound = min(recording.count - length, expectedStart + maxOffset)
        guard lowerBound <= upperBound else { return nil }

        var bestCorrelation: Double = -Double.greatestFiniteMagnitude
        var bestStart = expectedStart

        for start in lowerBound...upperBound {
            let correlation = normalizedCorrelation(at: start, recording: recording, reference: reference)
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestStart = start
            }
        }

        let latencySamples = bestStart - expectedStart
        let latencyMs = (Double(latencySamples) / sampleRate) * 1_000
        let confidence = bestCorrelation.clamped(to: 0...1)

        return LatencyDetection(latencyMs: latencyMs, correlation: confidence, sampleIndex: bestStart)
    }

    private func normalizedCorrelation(at start: Int, recording: [Float], reference: [Float]) -> Double {
        let length = reference.count
        guard start >= 0, start + length <= recording.count else { return 0 }

        var dot: Double = 0
        var refEnergy: Double = 0
        var windowEnergy: Double = 0

        for i in 0..<length {
            let r = Double(reference[i])
            let w = Double(recording[start + i])
            dot += r * w
            refEnergy += r * r
            windowEnergy += w * w
        }

        let denominator = sqrt(refEnergy * windowEnergy)
        guard denominator > 0 else { return 0 }
        return min(max(dot / denominator, 0), 1)
    }

    private func normalize(_ samples: [Float]) -> [Float] {
        guard let maxValue = samples.map({ abs($0) }).max(), maxValue > 0 else {
            return samples
        }

        return samples.map { $0 / maxValue }
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        let total = reduce(0, +)
        return total / Double(count)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
