import Foundation
import os

@Observable
final class PlexAPIContext {
    private(set) var authTokenCloud: String?
    private(set) var clientIdentifier: String = ""
    private var resource: PlexCloudResource?
    private(set) var baseURLServer: URL?
    private(set) var authTokenServer: String?
    private(set) var isRelayConnection = false
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    @ObservationIgnored private let clientIdKey = "slingshot.plex.clientId"
    @ObservationIgnored private let connectionKeyPrefix = "slingshot.plex.connection"

    init() {
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            let cid = try await ensureClientIdentifier()
            clientIdentifier = cid
        } catch {
            let fallback = UUID().uuidString
            clientIdentifier = fallback
        }
    }

    private func ensureClientIdentifier() async throws -> String {
        if let stored = try keychain.string(forKey: clientIdKey) {
            return stored
        }
        let identifier = UUID().uuidString
        try keychain.setString(identifier, forKey: clientIdKey)
        return identifier
    }

    func waitForBootstrap() async {
        await bootstrapTask?.value
    }

    func setAuthToken(_ token: String) {
        authTokenCloud = token
    }

    var serverIdentifier: String? {
        resource?.clientIdentifier
    }

    func selectServer(_ resource: PlexCloudResource) async throws {
        self.resource = resource
        baseURLServer = nil
        authTokenServer = resource.accessToken

        try await ensureConnection()
    }

    func removeServer() {
        resource = nil
        baseURLServer = nil
        authTokenServer = nil
        isRelayConnection = false
    }

    @discardableResult
    private func ensureConnection() async throws -> URL {
        guard let resource else {
            throw PlexAPIError.missingConnection
        }
        if let baseURLServer {
            return baseURLServer
        }

        guard let connection = await resolveConnection(using: resource) else {
            throw PlexAPIError.unreachableServer
        }

        baseURLServer = connection.uri
        isRelayConnection = connection.isRelay
        storeConnection(connection.uri, for: resource)
        return connection.uri
    }

    /// Race all connections concurrently, preferring local over remote over relay.
    /// If a non-local connection wins first, wait a brief grace period for a local
    /// one to come in before settling.
    private func resolveConnection(using resource: PlexCloudResource) async -> PlexCloudResource.Connection? {
        guard let connections = resource.connections, !connections.isEmpty else {
            return nil
        }

        let accessToken = resource.accessToken
        AppLogger.connection.info("Racing \(connections.count) connections")

        return await withCheckedContinuation { continuation in
            let state = ConnectionRaceState(connections: connections)

            for connection in connections {
                Task {
                    let reachable = await self.checkReachability(connection, accessToken: accessToken)
                    AppLogger.connection.debug("Connection \(connection.uri) reachable: \(reachable)")
                    guard reachable else {
                        if state.recordFailure() {
                            AppLogger.connection.warning("All connections failed")
                            continuation.resume(returning: nil)
                        }
                        return
                    }

                    let action = state.recordSuccess(connection)
                    switch action {
                    case let .resolve(winner):
                        AppLogger.connection.info("Selected connection: \(winner.uri) (local: \(winner.isLocal), relay: \(winner.isRelay))")
                        continuation.resume(returning: winner)
                    case .waitForLocal:
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            if let winner = state.settleWithBest() {
                                AppLogger.connection.info("Selected connection: \(winner.uri) (local: \(winner.isLocal), relay: \(winner.isRelay))")
                                continuation.resume(returning: winner)
                            }
                        }
                    case .none:
                        break
                    }
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if let winner = state.settleWithBest() {
                    AppLogger.connection.info("Selected connection: \(winner.uri) (local: \(winner.isLocal), relay: \(winner.isRelay))")
                    continuation.resume(returning: winner)
                } else if state.recordTimeout() {
                    AppLogger.connection.warning("Connection race timed out")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func checkReachability(
        _ connection: PlexCloudResource.Connection,
        accessToken: String?,
    ) async -> Bool {
        var request = URLRequest(url: connection.uri)
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "X-Plex-Token")
        }
        request.timeoutInterval = 6

        do {
            let (_, response) = try await PlexURLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode < 500
        } catch {
            return false
        }
    }

    func reset() {
        resource = nil
        authTokenCloud = nil
        baseURLServer = nil
        authTokenServer = nil
        isRelayConnection = false
    }

    private func connectionKey(for resource: PlexCloudResource) -> String {
        "\(connectionKeyPrefix).\(resource.clientIdentifier)"
    }

    private func loadSavedConnection(for resource: PlexCloudResource) -> URL? {
        do {
            guard let value = try keychain.string(forKey: connectionKey(for: resource)) else {
                return nil
            }
            return URL(string: value)
        } catch {
            return nil
        }
    }

    private func storeConnection(_ url: URL, for resource: PlexCloudResource) {
        do {
            try keychain.setString(url.absoluteString, forKey: connectionKey(for: resource))
        } catch {
            return
        }
    }
}

// MARK: - Connection Race

private final class ConnectionRaceState: @unchecked Sendable {
    enum Action {
        case resolve(PlexCloudResource.Connection)
        case waitForLocal
        case none
    }

    private let lock = NSLock()
    private let totalCount: Int
    private var failureCount = 0
    private var resolved = false
    private var gracePeriodStarted = false
    private var bestConnection: PlexCloudResource.Connection?

    init(connections: [PlexCloudResource.Connection]) {
        totalCount = connections.count
    }

    /// Record a successful connection. Returns the action the caller should take.
    func recordSuccess(_ connection: PlexCloudResource.Connection) -> Action {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return .none }

        // Track the best connection seen so far (local > remote > relay)
        if let current = bestConnection {
            if isBetter(connection, than: current) {
                bestConnection = connection
            }
        } else {
            bestConnection = connection
        }

        if connection.isLocal {
            // Local connection — resolve immediately, this is the best we can get
            resolved = true
            return .resolve(connection)
        }

        if !gracePeriodStarted {
            // First non-local success — give local connections a grace period
            gracePeriodStarted = true
            return .waitForLocal
        }

        return .none
    }

    /// Record a failed connection. Returns true if all connections have failed.
    func recordFailure() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        failureCount += 1
        guard !resolved, failureCount >= totalCount else { return false }
        resolved = true
        return true
    }

    /// Record overall timeout. Returns true if we should resolve with nil.
    func recordTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved else { return false }
        resolved = true
        return true
    }

    /// Settle with whatever the best connection is after the grace period.
    /// Returns nil if already resolved by someone else.
    func settleWithBest() -> PlexCloudResource.Connection? {
        lock.lock()
        defer { lock.unlock() }
        guard !resolved, let best = bestConnection else { return nil }
        resolved = true
        return best
    }

    private func isBetter(_ a: PlexCloudResource.Connection, than b: PlexCloudResource.Connection) -> Bool {
        if a.isLocal != b.isLocal { return a.isLocal }
        if a.isRelay != b.isRelay { return !a.isRelay }
        return false
    }
}
