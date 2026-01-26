import Foundation
import Observation

@MainActor
@Observable
final class SeerrViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let sessionManager: SessionManager

    var baseURLInput = ""
    var email = ""
    var password = ""
    var errorMessage = ""
    var isShowingError = false

    init(store: SeerrStore, sessionManager: SessionManager) {
        self.store = store
        self.sessionManager = sessionManager
        baseURLInput = store.baseURLString ?? ""
    }

    func validateServer() async {
        do {
            try await store.validateAndSaveBaseURL(baseURLInput)
        } catch {
            presentError(error)
        }
    }

    func signInWithPlex() async {
        guard let authToken = sessionManager.authToken else { return }

        do {
            try await store.signInWithPlex(authToken: authToken)
        } catch {
            presentError(error)
        }
    }

    func signInWithLocal() async {
        do {
            try await store.signInWithLocal(email: email, password: password)
            password = ""
        } catch {
            presentError(error)
        }
    }

    func signOut() {
        store.signOut()
    }

    var user: SeerrUser? {
        store.user
    }

    var baseURLString: String? {
        store.baseURLString
    }

    var isLoggedIn: Bool {
        store.isLoggedIn
    }

    var isAuthenticating: Bool {
        store.isAuthenticating
    }

    var isValidating: Bool {
        store.isValidating
    }

    var isPlexAuthAvailable: Bool {
        sessionManager.authToken != nil
    }

    private func presentError(_ error: Error) {
        let key = switch error {
        case SeerrAPIError.invalidURL:
            "integrations.seerr.error.invalidURL"
        case SeerrAPIError.requestFailed:
            "integrations.seerr.error.connection"
        default:
            "common.errors.tryAgainLater"
        }

        errorMessage = String(localized: .init(key))
        isShowingError = true
    }
}
