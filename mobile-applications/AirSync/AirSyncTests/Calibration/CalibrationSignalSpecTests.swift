import XCTest
@testable import AirSync

final class CalibrationSignalSpecTests: XCTestCase {
    func testDecodesClickStringVariant() throws {
        let json = "\"click\"".data(using: .utf8)!
        let kind = try JSONDecoder().decode(MarkerKind.self, from: json)
        XCTAssertEqual(kind, .click)
    }

    func testDecodesSerdeChirpObject() throws {
        let json = """
        {"kind":{"chirp":{"start_freq":2000,"end_freq":8000,"duration_ms":50}},"id":"m1","start_sample":0,"duration_samples":2400}
        """.data(using: .utf8)!
        let spec = try JSONDecoder().decode(MarkerSpec.self, from: json)
        XCTAssertEqual(spec.kind, .chirp(startFreq: 2000, endFreq: 8000, durationMs: 50))
        XCTAssertEqual(spec.id, "m1")
        XCTAssertEqual(spec.durationSamples, 2400)
    }
}
