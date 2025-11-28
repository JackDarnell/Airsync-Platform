import Foundation

final class ReceiverCalibrationClient: CalibrationAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func startPlayback(_ config: ChirpConfig) async throws {
        let payload = CalibrationRequestPayload(
            timestamp: Self.timestampNow(),
            chirpConfig: config
        )

        var request = URLRequest(url: endpoint(path: "api/calibration/request"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await session.data(for: request)
    }

    func submitResult(_ result: CalibrationResultPayload) async throws {
        var request = URLRequest(url: endpoint(path: "api/calibration/result"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(result)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await session.data(for: request)
    }

    private func endpoint(path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private static func timestampNow() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }
}
