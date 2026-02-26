import Foundation
import WatchConnectivity

final class PhoneSessionManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSessionManager()

    private var sessionManager: SessionManager?

    private override init() {
        super.init()
    }

    func activate(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendAuthToken(_ token: String, serverIdentifier: String?) {
        guard WCSession.default.activationState == .activated else { return }

        var userInfo: [String: Any] = ["authToken": token]
        if let serverIdentifier {
            userInfo["serverIdentifier"] = serverIdentifier
        }

        WCSession.default.transferUserInfo(userInfo)
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

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
