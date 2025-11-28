import SwiftUI

@MainActor
struct CalibrationView: View {
    @StateObject private var session: CalibrationSession
    @State private var isCalibrating = false

    init(session: CalibrationSession) {
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Calibration")
                    .font(.title.weight(.semibold))
                Text("Place your iPhone near the primary speaker. The receiver will play a short chirp sequence to measure latency.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            statusView

            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Measurement")
                    .font(.headline)
                if let measurement = session.latestMeasurement {
                    Text("Latency: \(Int(measurement.latencyMs)) ms")
                    Text("Confidence: \(Int(measurement.confidence * 100))%")
                } else {
                    Text("No calibration data yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task {
                    isCalibrating = true
                    await session.start()
                    isCalibrating = false
                }
            } label: {
                HStack {
                    if isCalibrating {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(isCalibrating ? "Calibrating..." : "Start Calibration")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isCalibrating)
        }
        .padding()
        .navigationTitle("Calibration")
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
            Text(statusText)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusText: String {
        switch session.stage {
        case .idle:
            return "Ready to calibrate."
        case .requestingPlayback:
            return "Asking receiver to play calibration chirps..."
        case .recording:
            return "Listening for chirps..."
        case .calculating:
            return "Calculating latency..."
        case .sending:
            return "Sending results to receiver..."
        case .completed:
            return "Calibration complete."
        case let .failed(message):
            return "Calibration failed: \(message)"
        }
    }
}

#Preview {
    NavigationStack {
        CalibrationView(
            session: .previewSession(
                measurement: LatencyMeasurement(latencyMs: 42, confidence: 0.92, detections: [])
            )
        )
    }
}
