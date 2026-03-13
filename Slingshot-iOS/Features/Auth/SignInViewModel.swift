import AuthenticationServices
import Foundation
import Observation
import os
import UIKit

@MainActor
@Observable
final class SignInViewModel {
    var isAuthenticating = false
    var errorMessage: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presentationContextProvider = WebAuthenticationPresentationContextProvider()
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let plexContext: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        plexContext = context
    }

    func startSignIn() async {
        cancelSignIn()
        errorMessage = nil
        isAuthenticating = true

        do {
            AppLogger.auth.info("Starting sign-in, requesting PIN...")
            let authRepository = AuthRepository(context: plexContext)
            let pinResponse = try await authRepository.requestPin()
            AppLogger.auth.info("PIN received: \(pinResponse.id), opening auth session...")

            let url = plexAuthURL(pin: pinResponse)
            let startedSession = await openAuthSession(url)

            guard startedSession else {
                AppLogger.auth.error("Auth session failed to start")
                throw SignInError.authSessionFailed
            }

            AppLogger.auth.info("Auth session started, beginning polling...")
            beginPolling(pinID: pinResponse.id)

        } catch {
            AppLogger.auth.error("Sign-in failed: \(error.localizedDescription)")
            errorMessage = String(localized: "signIn.error.startFailed")
            ErrorReporter.capture(error)
            cancelSignIn()
        }
    }

    func cancelSignIn() {
        isAuthenticating = false
        pollTask?.cancel()
        pollTask = nil

        authSession?.cancel()
        authSession = nil
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Slingshot" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)!
    }

    private func openAuthSession(_ url: URL) async -> Bool {
        authSession?.cancel()

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin
            {
                Task { @MainActor in
                    self?.cancelSignIn()
                }
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = presentationContextProvider
        authSession = session

        if session.start() {
            return true
        }

        authSession = nil
        return await openInSystemBrowser(url)
    }

    private func openInSystemBrowser(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
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
                            AppLogger.auth.info("Token received, signing in...")
                            try await sessionManager.signIn(with: token)
                            AppLogger.auth.info("Sign-in bootstrap complete")
                            cancelSignIn()
                            return
                        } catch {
                            AppLogger.auth.error("Bootstrap failed: \(error.localizedDescription)")
                            errorMessage = String(localized: "signIn.error.startFailed")
                            ErrorReporter.capture(error)
                            cancelSignIn()
                        }
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        AppLogger.auth.error("PIN expired (404)")
                        errorMessage = String(localized: "signIn.error.pinExpired")
                        cancelSignIn()
                        return
                    }

                    AppLogger.auth.error("Polling error: \(error.localizedDescription)")
                    errorMessage = String(localized: "signIn.error.startFailed")
                    ErrorReporter.capture(error)
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

private enum SignInError: Error {
    case authSessionFailed
}

private final class WebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        {
            return keyWindow
        }

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return ASPresentationAnchor(windowScene: scene)
        }

        return ASPresentationAnchor()
    }
}
