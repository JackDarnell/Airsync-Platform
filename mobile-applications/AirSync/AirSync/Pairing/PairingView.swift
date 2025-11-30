import SwiftUI
import UIKit

@MainActor
struct PairingView: View {
    let receiver: Receiver
    @ObservedObject var store: PairedReceiverStore
    @State private var startResponse: PairingStartResponse?
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

            if let output = startResponse?.outputDevice {
                Label("Output device: \(output)", systemImage: "speaker.wave.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(startResponse == nil ? "Connecting..." : "Connected")

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

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
