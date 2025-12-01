import Accelerate
import Foundation

struct StructuredDetection: Equatable {
    let markerId: String
    let markerStartSample: Int
    let latencyMs: Double
    let correlation: Double
    let sampleIndex: Int
}

final class StructuredDetector {
    private let maxWindowMs: Double
    private let sampleRate: Double

    init(sampleRate: Double, maxWindowMs: Double = 1200) {
        self.sampleRate = sampleRate
        self.maxWindowMs = maxWindowMs
    }

    func measure(
        recording: [Float],
        spec: CalibrationSignalSpec,
        startOffsetSamples: Int
    ) -> LatencyMeasurement {
        guard !recording.isEmpty else {
            return LatencyMeasurement(latencyMs: 0, confidence: 0, detections: [])
        }

        let normalizedRecording = normalize(recording)
        let maxOffset = Int(sampleRate * maxWindowMs / 1000.0)
        var detections: [StructuredDetection] = []

        let minCorrelation = 0.25
        for marker in spec.markers {
            let reference = referenceFor(marker: marker, sampleRate: sampleRate)
            let expected = Int(marker.startSample) + startOffsetSamples
            guard let det = findBestAlignment(
                expectedStart: expected,
                recording: normalizedRecording,
                reference: reference,
                maxOffset: maxOffset
            ) else { continue }

            guard det.correlation >= minCorrelation else { continue }

            let latencySamples = det.sampleIndex - expected
            let latencyMs = (Double(latencySamples) / sampleRate) * 1000.0
            print("marker \(marker.id) corr=\(det.correlation) idx=\(det.sampleIndex) latency_ms=\(latencyMs)")
            detections.append(
                StructuredDetection(
                    markerId: marker.id,
                    markerStartSample: Int(marker.startSample),
                    latencyMs: latencyMs,
                    correlation: det.correlation,
                    sampleIndex: det.sampleIndex
                )
            )
        }

        let inliers = filterOutliers(detections)
        let anchorCandidates = inliers.filter {
            !isWarmMarker($0.markerId) && $0.markerStartSample >= Int(sampleRate / 2)
        }
        let anchors = anchorCandidates.isEmpty ? inliers : anchorCandidates

        let playbackStarts = anchors.map { $0.sampleIndex - $0.markerStartSample }.sorted()
        let playbackStartSamples = medianInt(playbackStarts) ?? 0

        let latencySamples = playbackStartSamples - startOffsetSamples
        let latencyMs = (Double(latencySamples) / sampleRate) * 1000.0
        let clampedLatency = latencyMs < -5 ? 0 : latencyMs
        let playbackStartMs = (Double(playbackStartSamples) / sampleRate) * 1000.0
        print("Detector playback_start_ms=\(playbackStartMs) latency_ms=\(latencyMs) anchors=\(anchors.count)")

        let confidence = confidenceScore(detections: anchors, totalMarkers: spec.markers.count)

        let mappedDetections = inliers.map {
            LatencyDetection(
                markerId: $0.markerId,
                latencyMs: $0.latencyMs,
                correlation: $0.correlation,
                sampleIndex: $0.sampleIndex
            )
        }

        return LatencyMeasurement(latencyMs: clampedLatency, confidence: confidence, detections: mappedDetections)
    }

    private func referenceFor(marker: MarkerSpec, sampleRate: Double) -> [Float] {
        let len = Int(marker.durationSamples)
        switch marker.kind {
        case .click:
            return Array(repeating: 0.9, count: len)
        case let .chirp(startFreq, endFreq, durationMs):
            let sr = sampleRate
            let duration = Double(durationMs) / 1000.0
            let sweepK = (Double(endFreq) - Double(startFreq)) / duration
            let window = max(1, len - 1)
            return (0..<len).map { n in
                let t = Double(n) / sr
                let phase = 2.0 * .pi * (Double(startFreq) * t + 0.5 * sweepK * t * t / duration)
                let w = 0.5 * (1.0 - cos(2.0 * .pi * Double(n) / Double(window)))
                return Float(sin(phase) * 0.9 * w)
            }
        }
    }

    private func normalize(_ samples: [Float]) -> [Float] {
        guard let maxValue = samples.map({ abs($0) }).max(), maxValue > 0 else {
            return samples
        }
        return samples.map { $0 / maxValue }
    }

    private func findBestAlignment(
        expectedStart: Int,
        recording: [Float],
        reference: [Float],
        maxOffset: Int
    ) -> (sampleIndex: Int, correlation: Double)? {
        let length = reference.count
        let lowerBound = max(0, expectedStart - maxOffset)
        let upperBound = min(recording.count - length, expectedStart + maxOffset)
        guard lowerBound <= upperBound else { return nil }

        var bestCorrelation = -Double.greatestFiniteMagnitude
        var bestStart = expectedStart
        let step = 4

        for start in stride(from: lowerBound, through: upperBound, by: step) {
            let corr = normalizedCorrelation(at: start, recording: recording, reference: reference)
            if corr > bestCorrelation {
                bestCorrelation = corr
                bestStart = start
            }
        }

        // refine around bestStart
        let refineLower = max(lowerBound, bestStart - step)
        let refineUpper = min(upperBound, bestStart + step)
        for start in refineLower...refineUpper {
            let corr = normalizedCorrelation(at: start, recording: recording, reference: reference)
            if corr > bestCorrelation {
                bestCorrelation = corr;
                bestStart = start;
            }
        }

        return (bestStart, bestCorrelation)
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
        return min(abs(dot) / denominator, 1)
    }

    private func filterOutliers(_ detections: [StructuredDetection]) -> [StructuredDetection] {
        guard detections.count > 2 else { return detections }
        let latencies = detections.map(\.latencyMs)
        let median = latencies.median
        let deviations = latencies.map { abs($0 - median) }
        let mad = deviations.median
        let threshold = mad * 3.5 + 0.1
        return detections.filter { abs($0.latencyMs - median) <= threshold }
    }

    private func confidenceScore(detections: [StructuredDetection], totalMarkers: Int) -> Double {
        guard !detections.isEmpty else { return 0 }
        let corr = detections.map(\.correlation).average ?? 0
        let spread = detections.map(\.latencyMs).stddev ?? 0
        let spreadPenalty = max(0, 1 - (spread / 5.0))
        let coverage = min(1.0, Double(detections.count) / Double(max(1, totalMarkers)))
        var score = (corr * 0.6 + spreadPenalty * 0.2 + coverage * 0.2).clamped(to: 0...1)
        if detections.count < 2 {
            score *= 0.5
        }
        return score
    }

    private func isWarmMarker(_ id: String) -> Bool {
        id.lowercased().contains("warm")
    }

    private func medianInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }

    var median: Double {
        let sorted = self.sorted()
        let mid = count / 2
        if count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }

    var stddev: Double? {
        guard let avg = average else { return nil }
        let variance = reduce(0) { $0 + pow($1 - avg, 2) } / Double(count)
        return sqrt(variance)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
