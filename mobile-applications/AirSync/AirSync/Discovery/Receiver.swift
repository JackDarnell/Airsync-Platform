import Foundation

struct Receiver: Identifiable, Hashable {
    let id: UUID
    let receiverID: String
    let name: String
    let host: String
    let port: Int

    init(
        id: UUID = UUID(),
        receiverID: String? = nil,
        name: String,
        host: String,
        port: Int = 5000
    ) {
        self.id = id
        self.receiverID = receiverID ?? "\(host):\(port)"
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
