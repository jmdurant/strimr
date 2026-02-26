import AuthenticationServices
import os
import SwiftUI

private let authLog = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Auth")

struct WatchSignInView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

    @State private var isSigningIn = false
    @State private var pinCode: String?
    @State private var errorMessage: String?
    @State private var pollTask: Task<Void, Never>?
    @State private var authSession: ASWebAuthenticationSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "play.tv")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)

                    Text("Strimr")
                        .font(.title3)
                        .fontWeight(.bold)

                    Button {
                        Task { await signInWithBrowser() }
                    } label: {
                        Label("Sign In", systemImage: "person.crop.circle")
                    }
                    .disabled(isSigningIn)

                    Button {
                        Task { await signInWithPIN() }
                    } label: {
                        Label("Use Code", systemImage: "number")
                    }
                    .disabled(isSigningIn)

                    if let pinCode {
                        VStack(spacing: 8) {
                            Text("Enter this code at")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("plex.tv/link")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(pinCode)
                                .font(.title2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                        }
                        .padding(.top, 8)
                    }

                    if isSigningIn {
                        ProgressView()
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("Sign In")
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Strimr" +
            "&code=\(pin.code)"
        return URL(string: base + fragment)!
    }

    private func signInWithBrowser() async {
        cancelSignIn()
        isSigningIn = true
        errorMessage = nil
        pinCode = nil

        do {
            let authRepo = AuthRepository(context: plexApiContext)
            debugPrint("[Auth] Requesting PIN...")
            let pinResponse = try await authRepo.requestPin()
            let url = plexAuthURL(pin: pinResponse)
            debugPrint("[Auth] PIN received, opening URL:", url.absoluteString)
            debugPrint("[Auth] URL host:", url.host ?? "nil", "path:", url.path, "fragment:", url.fragment ?? "nil")

            authSession?.cancel()
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: nil
            ) { callbackURL, error in
                debugPrint("[Auth] ASWebAuth callback — url:", callbackURL?.absoluteString ?? "nil", "error:", error?.localizedDescription ?? "nil", "code:", (error as NSError?)?.code ?? -1)
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin
                {
                    Task { @MainActor in cancelSignIn() }
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            authSession = session

            let started = session.start()
            debugPrint("[Auth] session.start() returned:", started)

            guard started else {
                errorMessage = "Failed to start auth session"
                isSigningIn = false
                return
            }

            beginPolling(pinID: pinResponse.id)
        } catch {
            debugPrint("[Auth] Error:", error)
            errorMessage = error.localizedDescription
            isSigningIn = false
        }
    }

    private func signInWithPIN() async {
        cancelSignIn()
        isSigningIn = true
        errorMessage = nil

        do {
            let authRepo = AuthRepository(context: plexApiContext)
            let pinResponse = try await authRepo.requestPin()
            pinCode = pinResponse.code
            beginPolling(pinID: pinResponse.id)
        } catch {
            errorMessage = error.localizedDescription
            isSigningIn = false
            pinCode = nil
        }
    }

    private func beginPolling(pinID: Int) {
        pollTask?.cancel()

        pollTask = Task {
            while !Task.isCancelled, isSigningIn {
                do {
                    let authRepo = AuthRepository(context: plexApiContext)
                    let result = try await authRepo.pollToken(pinId: pinID)
                    if let token = result.authToken {
                        try await sessionManager.signIn(with: token)
                        cancelSignIn()
                        return
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        await MainActor.run {
                            errorMessage = "PIN expired, please try again"
                            cancelSignIn()
                        }
                        return
                    }
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func cancelSignIn() {
        isSigningIn = false
        pollTask?.cancel()
        pollTask = nil
        authSession?.cancel()
        authSession = nil
    }
}
