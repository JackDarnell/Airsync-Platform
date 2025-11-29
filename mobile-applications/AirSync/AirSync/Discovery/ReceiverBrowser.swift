import Combine
import Foundation
import Network

@MainActor
final class ReceiverBrowser: ObservableObject {
    @Published private(set) var receivers: [Receiver] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: "_airsync._tcp", domain: nil),
            using: parameters
        )

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let mapped = results.compactMap(Self.receiver(from:))
            Task { @MainActor in
                self?.receivers = mapped.sorted { $0.displayName < $1.displayName }
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready, .setup:
                    self?.isScanning = true
                    self?.lastError = nil
                case let .failed(error):
                    self?.isScanning = false
                    self?.lastError = Self.message(for: error)
                default:
                    self?.isScanning = false
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser
        isScanning = true
        lastError = nil
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    func refresh() {
        stop()
        start()
    }

    private static func receiver(from result: NWBrowser.Result) -> Receiver? {
        guard case let .service(name, _, domain, _) = result.endpoint else { return nil }
        let host = sanitizedHost(name: name, domain: domain)
        return Receiver(name: name, host: host)
    }

    private static func sanitizedHost(name: String, domain: String) -> String {
        let trimmedDomain = domain.hasSuffix(".") ? String(domain.dropLast()) : domain
        let normalizedName = name.replacingOccurrences(of: " ", with: "-")
        return "\(normalizedName).\(trimmedDomain)"
    }

    private static func message(for error: NWError) -> String {
        switch error {
        case let .dns(errorCode) where errorCode == DNSServiceErrorType(kDNSServiceErr_NoAuth):
            return "Local Network permission is required to discover receivers. Enable it in Settings > Privacy > Local Network."
        default:
            return "Discovery failed: \(error.localizedDescription)"
        }
    }
}
