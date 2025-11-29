import Foundation

/// Represents a discovered AirPlay receiver on the network
public struct Receiver: Identifiable, Equatable, Hashable {
    /// Unique identifier for SwiftUI List rendering
    public let id: UUID

    /// User-friendly name of the receiver (e.g., "Living Room Speaker")
    public let name: String

    /// Network hostname (e.g., "airsync-living.local")
    public let hostname: String

    /// Port number for AirPlay connection
    public let port: Int

    /// Display name for UI - uses name if available, falls back to hostname
    public var displayName: String {
        name.isEmpty ? hostname : name
    }

    /// Initialize a new receiver
    /// - Parameters:
    ///   - name: User-friendly name
    ///   - hostname: Network hostname
    ///   - port: Port number
    ///   - id: Optional UUID (auto-generated if not provided)
    public init(
        name: String,
        hostname: String,
        port: Int,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
    }

    // MARK: - Equatable

    /// Two receivers are equal if they have the same hostname and port
    /// (Name can change via mDNS updates, so we don't compare it)
    public static func == (lhs: Receiver, rhs: Receiver) -> Bool {
        lhs.hostname == rhs.hostname && lhs.port == rhs.port
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(hostname)
        hasher.combine(port)
    }
}
