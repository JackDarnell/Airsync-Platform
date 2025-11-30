import Foundation

struct PairingStartResponse: Codable, Equatable {
    let receiverID: String
    let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case receiverID = "receiver_id"
        case capabilities
    }
}

enum PairingError: LocalizedError, Equatable {
    case badStatus(Int)
    case decodingFailed
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case let .badStatus(code):
            return "Pairing failed with status code \(code)."
        case .decodingFailed:
            return "Pairing response was invalid."
        case let .network(error):
            return error.localizedDescription
        }
    }
}

final class ReceiverPairingClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func start(deviceName: String, appVersion: String, platform: String = "ios") async throws -> PairingStartResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pairing/start"))
        request.httpMethod = "POST"
        let body: [String: String] = [
            "device_name": deviceName,
            "app_version": appVersion,
            "platform": platform,
        ]
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await perform(request: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PairingError.badStatus(status)
        }

        do {
            return try JSONDecoder().decode(PairingStartResponse.self, from: data)
        } catch {
            throw PairingError.decodingFailed
        }
    }

    private func perform(request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw PairingError.network(urlError)
        }
    }
}
