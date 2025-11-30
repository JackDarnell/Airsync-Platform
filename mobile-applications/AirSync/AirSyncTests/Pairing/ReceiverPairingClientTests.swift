import XCTest
@testable import AirSync

final class ReceiverPairingClientTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testStartReturnsReceiverInfo() async throws {
        let expected = PairingStartResponse(receiverID: "rx-1", capabilities: ["calibration"], outputDevice: "hw:1,0")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/pairing/start")
            let data = try JSONEncoder().encode(expected)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = ReceiverPairingClient(baseURL: URL(string: "http://example.com")!, session: mockSession())
        let result = try await client.start(deviceName: "iPhone", appVersion: "1.0")
        XCTAssertEqual(result, expected)
    }

    func testBadStatusThrows() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = ReceiverPairingClient(baseURL: URL(string: "http://example.com")!, session: mockSession())
        do {
            _ = try await client.start(deviceName: "iPhone", appVersion: "1.0")
            XCTFail("expected error")
        } catch let error as PairingError {
            XCTAssertEqual(error, .badStatus(500))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

private func mockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
