import Combine
import Foundation

final class PairedReceiverStore: ObservableObject {
    @Published private(set) var pairedKeys: Set<String>
    private let storageKey = "paired_receivers_keys"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.array(forKey: storageKey) as? [String] {
            self.pairedKeys = Set(data)
        } else {
            self.pairedKeys = []
        }
    }

    func isPaired(_ receiver: Receiver) -> Bool {
        pairedKeys.contains(key(for: receiver))
    }

    func markPaired(_ receiver: Receiver) {
        let k = key(for: receiver)
        guard !pairedKeys.contains(k) else { return }
        pairedKeys.insert(k)
        defaults.set(Array(pairedKeys), forKey: storageKey)
    }

    private func key(for receiver: Receiver) -> String {
        receiver.receiverID
    }
}
