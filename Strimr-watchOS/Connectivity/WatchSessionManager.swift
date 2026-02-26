import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    private let tokenKey = "strimr.plex.authToken"
    private let serverIdKey = "strimr.plex.serverIdentifier"

    var onTokenReceived: ((String) -> Void)?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            debugPrint("WCSession activation failed:", error)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleReceivedData(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleReceivedData(message)
    }

    private func handleReceivedData(_ data: [String: Any]) {
        guard let token = data["authToken"] as? String else { return }

        try? keychain.setString(token, forKey: tokenKey)

        if let serverId = data["serverIdentifier"] as? String {
            UserDefaults.standard.set(serverId, forKey: serverIdKey)
        }

        onTokenReceived?(token)
    }
}
