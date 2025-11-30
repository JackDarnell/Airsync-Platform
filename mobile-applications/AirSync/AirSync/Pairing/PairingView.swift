import SwiftUI
import UIKit

@MainActor
struct PairingView: View {
    let receiver: Receiver
    @ObservedObject var store: PairedReceiverStore
    @State private var startResponse: PairingStartResponse?
    @State private var confirmResponse: PairingConfirmResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var navigateToCalibration = false

    var body: some View {
        VStack(spacing: 16) {
            NavigationLink(isActive: $navigateToCalibration) {
                CalibrationView(session: .liveReceiverSession(baseURL: receiver.baseURL))
            } label: {
                EmptyView()
            }
            .hidden()

            Text("Pair with \(receiver.displayName)")
                .font(.title2)
                .bold()

            if let start = startResponse {
                VStack(spacing: 8) {
                    Text("Confirm this code on the receiver")
                        .font(.headline)
                    Text(start.code)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text("Tap Confirm when the receiver shows the same code.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Requesting pairing code...")
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button(action: { Task { await startPairing() } }) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(action: { Task { await confirmPairing() } }) {
                    Label("Confirm", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(startResponse == nil || isLoading)
            }
            .padding(.top)

            Spacer()
        }
        .padding()
        .onAppear {
            Task { await startPairing() }
        }
    }

    private func startPairing() async {
        isLoading = true
        errorMessage = nil
        do {
            let client = ReceiverPairingClient(baseURL: receiver.baseURL)
            startResponse = try await client.start(deviceName: deviceName(), appVersion: appVersion())
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func confirmPairing() async {
        guard let start = startResponse else { return }
        isLoading = true
        errorMessage = nil
        do {
            let client = ReceiverPairingClient(baseURL: receiver.baseURL)
            confirmResponse = try await client.confirm(pairingID: start.pairingID, code: start.code)
            store.markPaired(receiver)
            navigateToCalibration = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deviceName() -> String {
        UIDevice.current.name
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
