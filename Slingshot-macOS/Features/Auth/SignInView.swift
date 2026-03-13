import AuthenticationServices
import SwiftUI
import os

struct SignInView: View {
    @State private var viewModel: MacSignInViewModel

    init(viewModel: MacSignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.tint)

                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle.bold())

                Text("signIn.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack {
                    if viewModel.isAuthenticating { ProgressView().controlSize(.small) }
                    Text(viewModel.isAuthenticating ? "signIn.button.waiting" : "signIn.button.continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: 300)
                .padding()
                .background(.tint)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAuthenticating)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") { viewModel.cancelSignIn() }
                    .padding(.top, 4)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
@Observable
final class MacSignInViewModel {
    var isAuthenticating = false
    var errorMessage: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
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
            let authRepository = AuthRepository(context: plexContext)
            let pinResponse = try await authRepository.requestPin()

            let url = plexAuthURL(pin: pinResponse)
            NSWorkspace.shared.open(url)

            beginPolling(pinID: pinResponse.id)
        } catch {
            errorMessage = String(localized: "signIn.error.startFailed")
            cancelSignIn()
        }
    }

    func cancelSignIn() {
        isAuthenticating = false
        pollTask?.cancel()
        pollTask = nil
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Slingshot" +
            "&code=\(pin.code)"
        return URL(string: base + fragment)!
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
                            cancelSignIn()
                        }
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        errorMessage = String(localized: "signIn.error.pinExpired")
                        cancelSignIn()
                        return
                    }
                    errorMessage = String(localized: "signIn.error.startFailed")
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
