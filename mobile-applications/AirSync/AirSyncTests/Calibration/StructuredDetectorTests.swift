import XCTest
@testable import AirSync

final class StructuredDetectorTests: XCTestCase {
    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Structured detector tests skipped on simulator to avoid multiple simulator spins.")
        #endif
    }

    func testDetectsOffsetWithClicksAndTones() {
        // Build a simple spec: click at 0, tone at 1000 samples.
        let spec = CalibrationSignalSpec(
            sampleRate: 48_000,
            lengthSamples: 4_000,
            markers: [
                MarkerSpec(id: "a", kind: .click, startSample: 0, durationSamples: 100),
                MarkerSpec(id: "b", kind: .chirp(startFreq: 2000, endFreq: 2000, durationMs: 50), startSample: 1_000, durationSamples: 2_400),
            ]
        )

        // Synthesize reference signal then shift by +500 samples
        let sr = 48_000.0
        let detector = StructuredDetector(sampleRate: sr, maxWindowMs: 800)
        let full = synthesizeSignal(spec: spec, sampleRate: sr)
        let offsetSamples = 500
        let recording = Array(repeating: Float(0), count: offsetSamples) + full

        let measurement = detector.measure(recording: recording, spec: spec, startOffsetSamples: 0)
        XCTAssertEqual(measurement.detections.count, 2)
        XCTAssertEqual(round(measurement.latencyMs), round(Double(offsetSamples) / sr * 1000))
        XCTAssertGreaterThan(measurement.confidence, 0.2)
    }

    private func synthesizeSignal(spec: CalibrationSignalSpec, sampleRate: Double) -> [Float] {
        var buffer = Array(repeating: Float(0), count: Int(spec.lengthSamples))

        for marker in spec.markers {
            let start = Int(marker.startSample)
            let len = Int(marker.durationSamples)
            switch marker.kind {
            case .click:
                for i in 0..<len {
                    buffer[start + i] = 0.9
                }
            case let .chirp(startFreq, _, durationMs):
                let sr = sampleRate
                let duration = Double(durationMs) / 1000.0
                let sweepK = (Double(startFreq) - Double(startFreq)) / duration
                let window = max(1, len - 1)
                for n in 0..<len {
                    let t = Double(n) / sr
                    let phase = 2.0 * .pi * (Double(startFreq) * t + 0.5 * sweepK * t * t / duration)
                    let w = 0.5 * (1.0 - cos(2.0 * .pi * Double(n) / Double(window)))
                    buffer[start + n] = Float(sin(phase) * 0.9 * w)
                }
            }
        }

        return buffer
    }
}
