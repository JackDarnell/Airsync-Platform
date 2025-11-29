import XCTest
import Network
@testable import AirSync

/// Tests for the ReceiverDiscovery service that finds AirPlay receivers via mDNS
final class ReceiverDiscoveryTests: XCTestCase {

    var discovery: ReceiverDiscovery!

    override func setUp() {
        super.setUp()
        discovery = ReceiverDiscovery()
    }

    override func tearDown() {
        discovery.stopDiscovery()
        discovery = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitialStateHasNoReceivers() {
        // Then: Initially no receivers discovered
        XCTAssertTrue(discovery.receivers.isEmpty)
    }

    func testInitialStateIsNotDiscovering() {
        // Then: Initially not discovering
        XCTAssertFalse(discovery.isDiscovering)
    }

    // MARK: - Discovery Lifecycle Tests

    func testStartDiscoverySetsIsDiscoveringTrue() {
        // When: Starting discovery
        discovery.startDiscovery()

        // Then: Is discovering flag is set
        XCTAssertTrue(discovery.isDiscovering)
    }

    func testStopDiscoverySetsIsDiscoveringFalse() {
        // Given: Discovery is running
        discovery.startDiscovery()
        XCTAssertTrue(discovery.isDiscovering)

        // When: Stopping discovery
        discovery.stopDiscovery()

        // Then: Is discovering flag is cleared
        XCTAssertFalse(discovery.isDiscovering)
    }

    func testStopDiscoveryClearsReceivers() {
        // Given: Discovery has found receivers (we'll simulate this)
        discovery.startDiscovery()
        // In real scenario, receivers would be populated via mDNS
        // For now, we test the cleanup behavior

        // When: Stopping discovery
        discovery.stopDiscovery()

        // Then: Receivers list is cleared
        XCTAssertTrue(discovery.receivers.isEmpty)
    }

    // MARK: - Service Type Tests

    func testServiceTypeIsAirPlay() {
        // Then: Service type is correctly set for AirPlay discovery
        XCTAssertEqual(discovery.serviceType, "_airplay._tcp")
    }

    // MARK: - Discovery Integration Tests (Async)

    func testDiscoveryFindsLocalTestReceiver() async throws {
        // Note: This test requires the local-testing Docker container to be running
        // Skip if not available in CI environment
        guard ProcessInfo.processInfo.environment["CI"] == nil else {
            throw XCTSkip("Skipping integration test in CI environment")
        }

        // Given: Expectation for receiver discovery
        let expectation = expectation(description: "Receiver discovered")
        expectation.expectedFulfillmentCount = 1

        // Observe receivers
        let cancellable = discovery.$receivers
            .dropFirst() // Skip initial empty state
            .sink { receivers in
                if receivers.contains(where: { $0.name.contains("AirSync") }) {
                    expectation.fulfill()
                }
            }

        // When: Starting discovery
        discovery.startDiscovery()

        // Then: Should discover receiver within 10 seconds
        await fulfillment(of: [expectation], timeout: 10.0)

        cancellable.cancel()
        discovery.stopDiscovery()
    }

    func testDiscoveryCanBeRestartedAfterStop() {
        // Given: Discovery was started and stopped
        discovery.startDiscovery()
        XCTAssertTrue(discovery.isDiscovering)

        discovery.stopDiscovery()
        XCTAssertFalse(discovery.isDiscovering)

        // When: Starting discovery again
        discovery.startDiscovery()

        // Then: Discovery is active again
        XCTAssertTrue(discovery.isDiscovering)
    }
}
