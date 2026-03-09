import SwiftUI

struct WatchPinCodeView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

    @State private var pinCode: String?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let pinCode {
                    Text("Enter this code at")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("plex.tv/link")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)

                    Text(pinCode)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.vertical, 8)

                    ProgressView()
                        .padding(.top, 4)

                    Text("Waiting for approval...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if isLoading, pinCode == nil {
                    ProgressView()
                    Text("Requesting code...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)

                    Button("Try Again") {
                        Task { await requestPin() }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Link Code")
        .task {
            await requestPin()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func requestPin() async {
        isLoading = true
        errorMessage = nil
        pinCode = nil
        pollTask?.cancel()

        do {
            let authRepo = AuthRepository(context: plexApiContext)
            let pinResponse = try await authRepo.requestPin(strong: false)
            pinCode = pinResponse.code
            isLoading = false
            beginPolling(pinID: pinResponse.id)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func beginPolling(pinID: Int) {
        pollTask?.cancel()

        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let authRepo = AuthRepository(context: plexApiContext)
                    let result = try await authRepo.pollToken(pinId: pinID)
                    if let token = result.authToken {
                        try await sessionManager.signIn(with: token)
                        return
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        await MainActor.run {
                            errorMessage = "Code expired, please try again"
                            pinCode = nil
                        }
                        return
                    }
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
