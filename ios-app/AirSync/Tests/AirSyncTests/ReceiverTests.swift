import XCTest
@testable import AirSync

/// Tests for the Receiver model representing discovered AirPlay receivers
final class ReceiverTests: XCTestCase {

    // MARK: - Initialization Tests

    func testReceiverInitialization() {
        // Given: Receiver properties
        let name = "AirSync Living Room"
        let hostname = "airsync-living.local"
        let port = 5000

        // When: Creating a receiver
        let receiver = Receiver(
            name: name,
            hostname: hostname,
            port: port
        )

        // Then: Properties are set correctly
        XCTAssertEqual(receiver.name, name)
        XCTAssertEqual(receiver.hostname, hostname)
        XCTAssertEqual(receiver.port, port)
    }

    func testReceiverHasUniqueIdentifier() {
        // Given: Two receivers with same properties
        let receiver1 = Receiver(
            name: "AirSync Test",
            hostname: "test.local",
            port: 5000
        )
        let receiver2 = Receiver(
            name: "AirSync Test",
            hostname: "test.local",
            port: 5000
        )

        // Then: Each receiver has a unique ID
        XCTAssertNotEqual(receiver1.id, receiver2.id)
    }

    func testReceiverEquality() {
        // Given: Two receivers with same hostname and port
        let receiver1 = Receiver(
            name: "AirSync 1",
            hostname: "test.local",
            port: 5000
        )
        let receiver2 = Receiver(
            name: "AirSync 2",  // Different name
            hostname: "test.local",
            port: 5000
        )

        // Then: Receivers are equal if hostname and port match
        // (Name can change via mDNS update)
        XCTAssertEqual(receiver1, receiver2)
    }

    func testReceiverInequalityDifferentHostname() {
        // Given: Two receivers with different hostnames
        let receiver1 = Receiver(
            name: "AirSync",
            hostname: "test1.local",
            port: 5000
        )
        let receiver2 = Receiver(
            name: "AirSync",
            hostname: "test2.local",
            port: 5000
        )

        // Then: Receivers are not equal
        XCTAssertNotEqual(receiver1, receiver2)
    }

    func testReceiverInequalityDifferentPort() {
        // Given: Two receivers with different ports
        let receiver1 = Receiver(
            name: "AirSync",
            hostname: "test.local",
            port: 5000
        )
        let receiver2 = Receiver(
            name: "AirSync",
            hostname: "test.local",
            port: 5001
        )

        // Then: Receivers are not equal
        XCTAssertNotEqual(receiver1, receiver2)
    }

    // MARK: - Display Name Tests

    func testDisplayNameWithCustomName() {
        // Given: Receiver with custom name
        let receiver = Receiver(
            name: "Living Room Speaker",
            hostname: "speaker.local",
            port: 5000
        )

        // Then: Display name uses custom name
        XCTAssertEqual(receiver.displayName, "Living Room Speaker")
    }

    func testDisplayNameFallsBackToHostname() {
        // Given: Receiver with empty name
        let receiver = Receiver(
            name: "",
            hostname: "airsync-kitchen.local",
            port: 5000
        )

        // Then: Display name falls back to hostname
        XCTAssertEqual(receiver.displayName, "airsync-kitchen.local")
    }
}
