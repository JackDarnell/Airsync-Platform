import SwiftUI

@MainActor
struct CalibrationView: View {
    @StateObject private var session: CalibrationSession
    @State private var isCalibrating = false
    @State private var isApplying = false
    @State private var volume: Double = 0.9

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
            frequencyRangeSection
            stepperSection
            progressSection
            calculationSection
            volumeSection
            applySection

            VStack(alignment: .leading, spacing: 8) {
                Text("Latest Measurement")
                    .font(.headline)
                if let measurement = session.latestMeasurement {
                    Text("Latency: \(Int(measurement.latencyMs)) ms")
                    Text("Confidence: \(Int(measurement.confidence * 100))%")
                    Text("Detections: \(measurement.detections.count)")
                } else {
                    Text("No calibration data yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task {
                    session.setAmplitude(volume)
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
                    Text(calibrationButtonText)
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
            micIndicator
        }
    }

    private var stepperSection: some View {
        let steps = [
            ("Scheduling playback", CalibrationStage.requestingPlayback),
            ("Listening for markers", CalibrationStage.recording),
            ("Analyzing recording", CalibrationStage.calculating),
            ("Sending result", CalibrationStage.sending),
            ("Completed", CalibrationStage.completed(LatencyMeasurement(latencyMs: 0, confidence: 0, detections: [])))
        ]

        let currentIndex: Int = {
            switch session.stage {
            case .requestingPlayback: return 0
            case .recording: return 1
            case .calculating: return 2
            case .sending: return 3
            case .completed, .failed: return 4
            case .idle: return 0
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Steps")
                .font(.headline)
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(idx == currentIndex ? Color.blue : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text(item.0)
                        .font(.footnote)
                        .foregroundStyle(idx <= currentIndex ? .primary : .secondary)
                }
            }
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playback Volume")
                .font(.headline)
            Slider(value: $volume, in: 0.5...1.0, step: 0.05)
            Text("Volume: \(Int(volume * 100))%")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var frequencyRangeSection: some View {
        Group {
            if let range = session.frequencyRange {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening Range")
                        .font(.headline)
                    Text("\(Int(range.0)) Hz – \(Int(range.1)) Hz")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Progress")
                .font(.headline)
            ProgressView(value: session.progress)
                .progressViewStyle(.linear)
            if session.progress > 0 && session.progress < 1 {
                let percent = Int(session.progress * 100)
                Text("\(percent)% (estimated)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if session.stage.isTerminal {
                Text("Done")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Waiting to start...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calculationSection: some View {
        Group {
            if session.stage == .calculating {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calculation")
                        .font(.headline)
                    ProgressView(value: session.calculationProgress)
                        .progressViewStyle(.linear)
                    Text("Analyzing chirps…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var micIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.micPulse ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 12, height: 12)
                .scaleEffect(session.micPulse ? 1.4 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: session.micPulse)
            Text(session.micPulse ? "Mic signal detected" : "Waiting for signal...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var applySection: some View {
        Group {
            if session.latestMeasurement != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        Task {
                            isApplying = true
                            await session.applyLatestMeasurement()
                            isApplying = false
                        }
                    } label: {
                        HStack {
                            if isApplying {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(isApplying ? "Applying..." : "Send to Receiver & Restart")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.9))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isApplying)

                    Text("Applies the measured latency to the receiver and restarts AirPlay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var calibrationButtonText: String {
        if isCalibrating {
            return "Calibrating..."
        } else if session.latestMeasurement != nil {
            return "Retry Calibration"
        } else {
            return "Start Calibration"
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
