import SwiftUI

@MainActor
struct ProfileSelectionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput: String = ""
    @FocusState private var isPinFieldFocused: Bool
    @State private var isShowingLogoutConfirmation = false

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            header

            if let error = viewModel.errorMessage {
                errorCard(error)
            }

            profilesGrid

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .help("Sign Out")
            }
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .task { await viewModel.loadUsers() }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            VStack(alignment: .leading, spacing: 16) {
                Text("auth.profile.pin.title")
                    .font(.headline)

                let userDisplayName: String = user.friendlyName ?? user.title ?? "?"
                Text("auth.profile.pin.prompt \(userDisplayName)")
                    .foregroundStyle(.secondary)

                SecureField("auth.profile.pin.placeholder", text: $pinInput)
                    .textContentType(.password)
                    .focused($isPinFieldFocused)
                    .padding()
                    .background(.gray.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    Spacer()
                    Button("common.actions.cancel", role: .cancel) {
                        resetPinPrompt()
                    }
                }
            }
            .padding(24)
            .frame(width: 320)
            .onAppear { isPinFieldFocused = true }
        }
        .onChange(of: pinInput) { _, newValue in
            let sanitizedValue = String(newValue.filter(\.isNumber).prefix(4))
            if sanitizedValue != pinInput {
                pinInput = sanitizedValue
                return
            }
            submitPinIfComplete()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("auth.profile.header.title")
                .font(.largeTitle.bold())
            Text("auth.profile.header.subtitle")
                .foregroundStyle(.secondary)
        }
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 20)], spacing: 20) {
            if viewModel.users.isEmpty {
                loadingState
            }
            ForEach(viewModel.users) { user in
                profileCard(for: user)
            }
        }
        .frame(maxWidth: 700)
    }

    @ViewBuilder
    private var loadingState: some View {
        if viewModel.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("auth.profile.loading")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
        } else {
            Text("auth.profile.empty")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private func profileCard(for user: PlexHomeUser) -> some View {
        Button {
            if user.protected ?? false {
                pinPromptUser = user
                pinInput = ""
                isPinFieldFocused = true
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 10) {
                avatarView(for: user)
                    .frame(width: 120, height: 120)
                    .overlay(alignment: .topTrailing) {
                        if user.protected ?? false {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.primary.opacity(0.9))
                                .padding(8)
                        } else if viewModel.activeUserUUID == user.uuid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .padding(8)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                Color.primary.opacity(viewModel.activeUserUUID == user.uuid ? 0.8 : 0.25),
                                lineWidth: viewModel.activeUserUUID == user.uuid ? 2 : 1
                            )
                    )

                VStack(spacing: 4) {
                    Text(user.friendlyName ?? user.title ?? "?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(user.username ?? user.email ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func avatarView(for user: PlexHomeUser) -> some View {
        ZStack {
            if let url = user.thumb {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderAvatar
                }
            } else {
                placeholderAvatar
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if viewModel.switchingUserUUID == user.uuid {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var placeholderAvatar: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(24)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.primary)

            Button {
                Task { await viewModel.loadUsers() }
            } label: {
                Text("common.actions.retry")
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func resetPinPrompt() {
        pinPromptUser = nil
        pinInput = ""
        isPinFieldFocused = false
    }

    private func submitPinIfComplete() {
        guard pinInput.count == 4, let user = pinPromptUser else { return }
        let enteredPin = pinInput
        Task { await viewModel.switchToUser(user, pin: enteredPin) }
        resetPinPrompt()
    }
}
