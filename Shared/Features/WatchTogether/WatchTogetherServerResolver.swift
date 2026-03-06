import Foundation
import Network

@MainActor
final class WatchTogetherServerResolver {
    private static let defaultPort = 8080
    private static let mdnsServiceType = "_watchtogether._tcp"
    private static let mdnsTimeout: TimeInterval = 3

    private let settingsManager: SettingsManager
    private let context: PlexAPIContext

    init(settingsManager: SettingsManager, context: PlexAPIContext) {
        self.settingsManager = settingsManager
        self.context = context
    }

    /// Resolve the Watch Together server URL using the fallback chain:
    /// 1. Custom URL from settings (user-configured)
    /// 2. Info.plist build-time default (if not localhost)
    /// 3. Same host as the connected Plex server
    /// 4. mDNS auto-discovery on the local network
    func resolve() async -> URL? {
        if let url = customURL() {
            return url
        }

        if let url = infoPlistURL(), url.host != "localhost" {
            return url
        }

        if let url = plexServerURL() {
            return url
        }

        if let url = await discoverViaMDNS() {
            return url
        }

        // Final fallback: Info.plist even if localhost (simulator use)
        if let url = infoPlistURL() {
            return url
        }

        return nil
    }

    // MARK: - 1. Custom URL

    private func customURL() -> URL? {
        guard let raw = settingsManager.watchTogether.customServerURL, !raw.isEmpty else {
            return nil
        }
        return buildWebSocketURL(from: raw)
    }

    // MARK: - 2. Info.plist

    private func infoPlistURL() -> URL? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "WATCH_TOGETHER_URL") as? String,
              !urlString.isEmpty
        else {
            return nil
        }
        return URL(string: urlString)
    }

    // MARK: - 3. Plex Server Host

    private func plexServerURL() -> URL? {
        guard let baseURL = context.baseURLServer, let host = baseURL.host else {
            return nil
        }
        return buildWebSocketURL(from: "\(host):\(Self.defaultPort)")
    }

    // MARK: - 4. mDNS Discovery

    private func discoverViaMDNS() async -> URL? {
        await MDNSDiscovery.discover(
            serviceType: Self.mdnsServiceType,
            timeout: Self.mdnsTimeout
        )
    }

    // MARK: - Helpers

    private func buildWebSocketURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ws://") || trimmed.hasPrefix("wss://") {
            return URL(string: trimmed)
        }
        return URL(string: "wss://\(trimmed)")
    }
}

// MARK: - mDNS Discovery (non-isolated to avoid @MainActor + GCD conflicts)

private enum MDNSDiscovery {
    static func discover(serviceType: String, timeout: TimeInterval) async -> URL? {
        await withCheckedContinuation { continuation in
            let state = DiscoveryState()
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)

            let timeoutItem = DispatchWorkItem { [weak browser] in
                guard state.tryComplete() else { return }
                browser?.cancel()
                continuation.resume(returning: nil)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

            browser.browseResultsChangedHandler = { [weak browser] results, _ in
                guard let result = results.first else { return }
                let connection = NWConnection(to: result.endpoint, using: .tcp)
                connection.stateUpdateHandler = { [weak browser] connState in
                    switch connState {
                    case .ready:
                        guard state.tryComplete() else {
                            connection.cancel()
                            return
                        }
                        timeoutItem.cancel()
                        browser?.cancel()

                        var url: URL?
                        if let remote = connection.currentPath?.remoteEndpoint,
                           case let .hostPort(host: host, port: port) = remote
                        {
                            let hostStr: String
                            switch host {
                            case let .ipv4(addr): hostStr = "\(addr)"
                            case let .ipv6(addr): hostStr = "[\(addr)]"
                            case let .name(name, _): hostStr = name
                            @unknown default: hostStr = "\(host)"
                            }
                            url = URL(string: "ws://\(hostStr):\(port)")
                        }
                        connection.cancel()
                        continuation.resume(returning: url)
                    case .failed:
                        connection.cancel()
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }

            browser.start(queue: .global())
        }
    }
}

private final class DiscoveryState: @unchecked Sendable {
    private var completed = false
    private let lock = NSLock()

    func tryComplete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
