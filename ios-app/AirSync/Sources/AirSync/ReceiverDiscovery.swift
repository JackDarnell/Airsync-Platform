import Foundation
import Network
import Combine

/// Service for discovering AirPlay receivers on the local network via mDNS/Bonjour
@available(iOS 13.0, macOS 10.15, *)
public final class ReceiverDiscovery: ObservableObject {

    // MARK: - Published Properties

    /// List of currently discovered receivers
    @Published public private(set) var receivers: [Receiver] = []

    /// Whether discovery is currently active
    @Published public private(set) var isDiscovering: Bool = false

    // MARK: - Public Properties

    /// mDNS service type for AirPlay discovery
    public let serviceType: String = "_airplay._tcp"

    // MARK: - Private Properties

    private var browser: NWBrowser?
    private var receiverCache: [String: Receiver] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Start discovering AirPlay receivers on the network
    public func startDiscovery() {
        guard !isDiscovering else { return }

        isDiscovering = true
        receiverCache.removeAll()
        receivers = []

        // Create browser for AirPlay service type
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)

        // Handle discovered services
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results, changes: changes)
        }

        // Handle state changes
        browser?.stateUpdateHandler = { [weak self] state in
            self?.handleStateUpdate(state)
        }

        // Start browsing
        browser?.start(queue: .main)
    }

    /// Stop discovering receivers and clear the list
    public func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isDiscovering = false
        receiverCache.removeAll()
        receivers = []
    }

    // MARK: - Private Methods

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                handleReceiverAdded(result)
            case .removed(let result):
                handleReceiverRemoved(result)
            case .changed(let old, let new, _):
                handleReceiverChanged(old: old, new: new)
            case .identical:
                break
            @unknown default:
                break
            }
        }
    }

    private func handleReceiverAdded(_ result: NWBrowser.Result) {
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
            return
        }

        // Create unique key for this receiver
        let key = "\(name).\(type).\(domain)"

        // Resolve the service to get hostname and port
        resolveService(result) { [weak self] receiver in
            guard let self = self else { return }

            self.receiverCache[key] = receiver

            // Update receivers array
            DispatchQueue.main.async {
                self.updateReceiversList()
            }
        }
    }

    private func handleReceiverRemoved(_ result: NWBrowser.Result) {
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
            return
        }

        let key = "\(name).\(type).\(domain)"
        receiverCache.removeValue(forKey: key)

        DispatchQueue.main.async {
            self.updateReceiversList()
        }
    }

    private func handleReceiverChanged(old: NWBrowser.Result, new: NWBrowser.Result) {
        // Remove old and add new
        handleReceiverRemoved(old)
        handleReceiverAdded(new)
    }

    private func handleStateUpdate(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            print("🔍 Discovery started - browsing for \(serviceType)")
        case .failed(let error):
            print("❌ Discovery failed: \(error)")
            isDiscovering = false
        case .cancelled:
            print("⏹️ Discovery cancelled")
            isDiscovering = false
        default:
            break
        }
    }

    private func resolveService(_ result: NWBrowser.Result, completion: @escaping (Receiver) -> Void) {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return
        }

        // Create connection to resolve endpoint
        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = endpoint {

                    let hostname: String
                    switch host {
                    case .name(let name, _):
                        hostname = name
                    case .ipv4(let address):
                        hostname = address.debugDescription
                    case .ipv6(let address):
                        hostname = address.debugDescription
                    @unknown default:
                        hostname = "unknown"
                    }

                    let receiver = Receiver(
                        name: name,
                        hostname: hostname,
                        port: Int(port.rawValue)
                    )

                    completion(receiver)
                }
                connection.cancel()

            case .failed, .cancelled:
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: .main)
    }

    private func updateReceiversList() {
        receivers = Array(receiverCache.values).sorted { $0.name < $1.name }
    }
}
