import Foundation

struct Receiver: Identifiable, Hashable {
    let id: UUID
    let name: String
    let host: String
    let port: Int

    init(id: UUID = UUID(), name: String, host: String, port: Int = 5000) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
    }

    var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    var displayName: String {
        name.isEmpty ? host : name
    }
}
