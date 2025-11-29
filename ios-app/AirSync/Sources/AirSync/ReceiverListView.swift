import SwiftUI

/// SwiftUI view displaying discovered AirPlay receivers
@available(iOS 13.0, macOS 10.15, *)
public struct ReceiverListView: View {

    // MARK: - Properties

    @ObservedObject private var discovery: ReceiverDiscovery

    // MARK: - Initialization

    public init(discovery: ReceiverDiscovery = ReceiverDiscovery()) {
        self.discovery = discovery
    }

    // MARK: - Body

    public var body: some View {
        NavigationView {
            VStack {
                if discovery.receivers.isEmpty {
                    emptyStateView
                } else {
                    receiverList
                }
            }
            .onAppear {
                discovery.startDiscovery()
            }
            .onDisappear {
                discovery.stopDiscovery()
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            if discovery.isDiscovering {
                Text("⏳")
                    .font(.system(size: 60))
                    .padding()

                Text("Searching for AirPlay receivers...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Make sure your receiver is on the same network")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("📡")
                    .font(.system(size: 60))
                    .padding()

                Text("No Receivers Found")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Start discovery to find AirPlay receivers on your network")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    private var receiverList: some View {
        List(discovery.receivers) { receiver in
            ReceiverRow(receiver: receiver)
        }
    }
}

/// Row view for a single receiver
@available(iOS 13.0, macOS 10.15, *)
struct ReceiverRow: View {

    let receiver: Receiver

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(receiver.displayName)
                .font(.headline)

            Text(receiver.hostname)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Port: \(receiver.port)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

@available(iOS 13.0, macOS 10.15, *)
struct ReceiverListView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview with empty state
        ReceiverListView()

        // Preview with mock receivers
        ReceiverListView(discovery: {
            let discovery = ReceiverDiscovery()
            // In a real preview, you'd inject mock receivers
            return discovery
        }())
    }
}
