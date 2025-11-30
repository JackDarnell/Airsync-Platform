import Foundation

final class ReceiverCalibrationClient: CalibrationAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func serverTimeMs() async throws -> UInt64 {
        let request = URLRequest(url: endpoint(path: "api/time"))
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(TimeSyncResponse.self, from: data)
        return response.serverTimeMs
    }

    func startPlayback(_ config: ChirpConfig, delayMs: UInt64) async throws {
        let payload = CalibrationRequestPayload(
            timestamp: Self.timestampNow(),
            chirpConfig: config,
            delayMs: delayMs
        )

        var request = URLRequest(url: endpoint(path: "api/calibration/request"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await session.data(for: request)
    }

    func triggerPlayback(targetStartMs: UInt64) async throws {
        var request = URLRequest(url: endpoint(path: "api/calibration/ready"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(
            CalibrationReadyPayload(
                timestamp: Self.timestampNow(),
                targetStartMs: targetStartMs
            )
        )
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

private struct TimeSyncResponse: Decodable {
    let serverTimeMs: UInt64

    enum CodingKeys: String, CodingKey {
        case serverTimeMs = "server_time_ms"
    }
}

private struct CalibrationReadyPayload: Encodable {
    let timestamp: UInt64
    let targetStartMs: UInt64

    enum CodingKeys: String, CodingKey {
        case timestamp
        case targetStartMs = "target_start_ms"
    }
}
