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

        let reversedReference = Array(normalizedReference.reversed())
        var correlation = [Float](repeating: 0, count: normalizedRecording.count + normalizedReference.count - 1)
        vDSP_conv(normalizedRecording, 1, reversedReference, 1, &correlation, 1, vDSP_Length(normalizedRecording.count), vDSP_Length(normalizedReference.count))

        let baseOffset = normalizedReference.count - 1
        let maxLatencySamples = Int(sampleRate * maximumLatencyMs / 1_000)

        var detections: [LatencyDetection] = []

        for expectedStart in sequence.expectedStartSamples {
            guard let peakIndex = peakIndex(
                in: correlation,
                expectedStart: expectedStart,
                baseOffset: baseOffset,
                maxLatencySamples: maxLatencySamples
            ) else { continue }

            let actualStart = peakIndex - baseOffset
            let latencySamples = actualStart - expectedStart
            let latencyMs = (Double(latencySamples) / sampleRate) * 1_000
            let correlationScore = normalizedCorrelation(
                at: actualStart,
                recording: normalizedRecording,
                reference: normalizedReference
            )

            detections.append(
                LatencyDetection(
                    latencyMs: latencyMs,
                    correlation: correlationScore,
                    sampleIndex: actualStart
                )
            )
        }

        let averageLatency = detections.map(\.latencyMs).average ?? 0
        let rawConfidence = detections.map(\.correlation).average ?? 0
        let confidence = rawConfidence.clamped(to: 0...1)

        return LatencyMeasurement(latencyMs: averageLatency, confidence: confidence, detections: detections)
    }

    private func peakIndex(
        in correlation: [Float],
        expectedStart: Int,
        baseOffset: Int,
        maxLatencySamples: Int
    ) -> Int? {
        let searchStart = baseOffset + expectedStart
        let searchEnd = min(correlation.count - 1, searchStart + maxLatencySamples)
        guard searchStart < correlation.count, searchStart <= searchEnd else {
            return nil
        }

        var maxValue: Float = -Float.greatestFiniteMagnitude
        var indexOfMax = searchStart

        for index in searchStart...searchEnd {
            let value = correlation[index]
            if value > maxValue {
                maxValue = value
                indexOfMax = index
            }
        }

        return indexOfMax
    }

    private func normalizedCorrelation(at start: Int, recording: [Float], reference: [Float]) -> Double {
        let length = reference.count
        guard start >= 0, start + length <= recording.count else { return 0 }

        let window = Array(recording[start..<(start + length)])

        var dot: Float = 0
        vDSP_dotpr(window, 1, reference, 1, &dot, vDSP_Length(length))

        var referenceEnergy: Float = 0
        vDSP_svesq(reference, 1, &referenceEnergy, vDSP_Length(length))

        var windowEnergy: Float = 0
        vDSP_svesq(window, 1, &windowEnergy, vDSP_Length(length))

        let denominator = sqrt(referenceEnergy * windowEnergy)
        guard denominator > 0 else { return 0 }
        let score = Double(dot / denominator)
        return min(max(score, 0), 1)
    }

    private func normalize(_ samples: [Float]) -> [Float] {
        var maxValue: Float = 0
        vDSP_maxmgv(samples, 1, &maxValue, vDSP_Length(samples.count))
        guard maxValue > 0 else { return samples }
        let scale = 1 / maxValue
        var output = [Float](repeating: 0, count: samples.count)
        vDSP_vsmul(samples, 1, [scale], &output, 1, vDSP_Length(samples.count))
        return output
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
