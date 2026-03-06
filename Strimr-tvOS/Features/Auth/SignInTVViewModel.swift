import Foundation
import Observation

enum SignInMethod: String, CaseIterable {
    case credentials = "Sign In"
    case qrCode = "QR Code"
}

@MainActor
@Observable
final class SignInTVViewModel {
    var isAuthenticating = false
    var errorMessage: String?
    var pin: PlexCloudPin?
    var signInMethod: SignInMethod = .credentials
    var email = ""
    var password = ""

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let plexContext: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        plexContext = context
    }

    // MARK: - Email/Password Sign In

    func signInWithCredentials() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        cancelSignIn()
        errorMessage = nil
        isAuthenticating = true

        do {
            let authRepository = AuthRepository(context: plexContext)
            let user = try await authRepository.signIn(login: email, password: password)
            try await sessionManager.signIn(with: user.authToken)
            isAuthenticating = false
        } catch {
            if case PlexAPIError.requestFailed(statusCode: let code) = error {
                if code == 401 {
                    errorMessage = "Invalid email or password."
                } else {
                    errorMessage = "Sign in failed (HTTP \(code))."
                }
            } else {
                errorMessage = "Sign in failed: \(error.localizedDescription)"
                ErrorReporter.capture(error)
            }
            isAuthenticating = false
        }
    }

    // MARK: - QR Code Sign In

    func startQRSignIn() async {
        cancelSignIn()
        errorMessage = nil
        isAuthenticating = true

        do {
            try await requestNewPinAndBeginPolling()
        } catch {
            errorMessage = String(localized: "signIn.error.startFailed")
            ErrorReporter.capture(error)
            isAuthenticating = false
        }
    }

    func cancelSignIn() {
        isAuthenticating = false
        pollTask?.cancel()
        pollTask = nil
        pin = nil
    }

    private func beginPolling(pinID: Int) {
        pollTask?.cancel()

        pollTask = Task {
            while !Task.isCancelled, isAuthenticating {
                do {
                    let authRepository = AuthRepository(context: plexContext)
                    let result = try await authRepository.pollToken(pinId: pinID)
                    if let token = result.authToken {
                        do {
                            try await sessionManager.signIn(with: token)
                            cancelSignIn()
                            return
                        } catch {
                            errorMessage = String(localized: "signIn.error.startFailed")
                            ErrorReporter.capture(error)
                            cancelSignIn()
                        }
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        do {
                            try await requestNewPinAndBeginPolling()
                            return
                        } catch {
                            errorMessage = String(localized: "signIn.error.startFailed")
                            ErrorReporter.capture(error)
                            cancelSignIn()
                            return
                        }
                    }

                    errorMessage = String(localized: "signIn.error.startFailed")
                    ErrorReporter.capture(error)
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func requestNewPinAndBeginPolling() async throws {
        let authRepository = AuthRepository(context: plexContext)
        let pinResponse = try await authRepository.requestPin()
        pin = pinResponse
        beginPolling(pinID: pinResponse.id)
    }
}
