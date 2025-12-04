#if os(tvOS)
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SignInTVView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexContext

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var pin: PlexCloudPin?
    @State private var pollTask: Task<Void, Never>?

    private let ciContext = CIContext()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle.bold())

                Text("signIn.tv.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Group {
                if let pin {
                    VStack(spacing: 20) {
                        if let url = plexAuthURL(pin: pin),
                           let qrImage = qrImage(from: url.absoluteString)
                        {
                            Image(uiImage: qrImage)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 260, height: 260)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            ProgressView("signIn.button.waiting")
                                .progressViewStyle(.circular)
                        }

                        Text("signIn.tv.codeLabel \(pin.code)")
                            .font(.title2.monospacedDigit())
                            .fontWeight(.bold)
                    }
                } else if isAuthenticating {
                    ProgressView("signIn.button.waiting")
                        .progressViewStyle(.circular)
                }
            }

            Spacer()
        }
        .padding(48)
        .onAppear { Task { await startSignIn() } }
        .onDisappear { cancelSignIn() }
    }
}

extension SignInTVView {
    private func qrImage(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii) else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL? {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Strimr" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)
    }

    @MainActor
    private func startSignIn() async {
        resetSignInState()
        errorMessage = nil
        isAuthenticating = true

        do {
            let authRepository = AuthRepository(context: plexContext)
            let pinResponse = try await authRepository.requestPin()
            pin = pinResponse
            beginPolling(pinID: pinResponse.id)
        } catch {
            errorMessage = String(localized: "signIn.error.startFailed", bundle: .main)
            isAuthenticating = false
        }
    }

    @MainActor
    private func beginPolling(pinID: Int) {
        pollTask?.cancel()

        pollTask = Task {
            while !Task.isCancelled && isAuthenticating {
                do {
                    let authRepository = AuthRepository(context: plexContext)
                    let result = try await authRepository.pollToken(pinId: pinID)
                    if let token = result.authToken {
                        await sessionManager.signIn(with: token)
                        cancelSignIn()
                        return
                    }
                } catch {
                    // ignore and keep polling
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @MainActor
    private func cancelSignIn() {
        isAuthenticating = false
        resetSignInState()
    }

    @MainActor
    private func resetSignInState() {
        pollTask?.cancel()
        pollTask = nil
        pin = nil
    }
}
#endif
