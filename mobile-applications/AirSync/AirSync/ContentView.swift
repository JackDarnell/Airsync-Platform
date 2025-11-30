//
//  ContentView.swift
//  AirSync
//
//  Created by Jack Darnell on 11/27/25.
//

import AVFoundation
import UIKit
import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var browser = ReceiverBrowser()
    @State private var manualHost: String = ""
    @State private var microphonePermission: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission

    var body: some View {
        NavigationStack {
            List {
                if browser.needsLocalNetworkPermission || microphonePermission != .granted {
                    Section(header: Text("Permissions")) {
                        if browser.needsLocalNetworkPermission {
                            VStack(alignment: .leading, spacing: 8) {
                                Label {
                                    Text("Allow Local Network access to discover receivers on your Wi‑Fi.")
                                } icon: {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }

                                HStack {
                                    Button("Open Settings") {
                                        openSettings()
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Try Again") {
                                        browser.refresh()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        if microphonePermission != .granted {
                            VStack(alignment: .leading, spacing: 8) {
                                Label {
                                    Text("Microphone access is needed to record calibration chirps.")
                                } icon: {
                                    Image(systemName: "mic.fill")
                                }

                                HStack {
                                    if microphonePermission == .undetermined {
                                        Button("Allow Microphone") {
                                            requestMicrophonePermission()
                                        }
                                        .buttonStyle(.borderedProminent)
                                    } else {
                                        Button("Open Settings") {
                                            openSettings()
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    Text(statusText(for: microphonePermission))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let error = browser.lastError {
                    Section {
                        Label {
                            Text(error)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section(header: Text("Discovered Receivers")) {
                    if browser.receivers.isEmpty {
                        Text(browser.isScanning ? "Scanning the local network..." : "No receivers found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(browser.receivers) { receiver in
                            NavigationLink(destination: CalibrationView(session: .liveReceiverSession(baseURL: receiver.baseURL))) {
                                VStack(alignment: .leading) {
                                    Text(receiver.displayName)
                                        .font(.headline)
                                    Text(receiver.host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Manual Address")) {
                    HStack {
                        TextField("receiver.local or IP", text: $manualHost)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                        if let receiver = manualReceiver {
                            NavigationLink("Calibrate") {
                                CalibrationView(session: .liveReceiverSession(baseURL: receiver.baseURL))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Receiver")
            .toolbar {
                Button {
                    browser.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .onAppear {
                browser.start()
                refreshMicrophonePermission()
            }
        }
    }

    private var manualReceiver: Receiver? {
        guard !manualHost.isEmpty, let url = URL(string: "http://\(manualHost):5000") else { return nil }
        return Receiver(
            receiverID: manualHost,
            name: manualHost,
            host: url.host ?? manualHost,
            port: url.port ?? 5000
        )
    }

    private func refreshMicrophonePermission() {
        microphonePermission = AVAudioSession.sharedInstance().recordPermission
    }

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                microphonePermission = granted ? .granted : .denied
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func statusText(for permission: AVAudioSession.RecordPermission) -> String {
        switch permission {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied in Settings"
        case .undetermined:
            return "Not requested"
        @unknown default:
            return "Unknown"
        }
    }
}

#Preview {
    ContentView()
}
