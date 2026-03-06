import SwiftUI

@MainActor
struct WatchTogetherView: View {
    @Environment(WatchTogetherViewModel.self) private var viewModel
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @State private var isShowingLeavePrompt = false

    var body: some View {
        ZStack(alignment: .top) {
            content()
        }
        .navigationTitle("Watch Together")
        .toolbar {
            if viewModel.isInSession {
                ToolbarItem(placement: .automatic) {
                    Button("Leave") {
                        isShowingLeavePrompt = true
                    }
                }
            }
        }
        .alert("Leave Session", isPresented: $isShowingLeavePrompt) {
            Button("Leave (just me)") {
                viewModel.leaveSession(endForAll: false)
            }

            if viewModel.isHost {
                Button("End for everyone", role: .destructive) {
                    viewModel.leaveSession(endForAll: true)
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this Watch Together session?")
        }
        .overlay(alignment: .top) {
            ToastOverlay(toasts: viewModel.toasts)
        }
    }

    @ViewBuilder
    private func content() -> some View {
        if viewModel.isInSession {
            lobbyView()
        } else {
            entryView()
        }
    }

    private func entryView() -> some View {
        let joinCodeBinding = Binding(
            get: { viewModel.joinCode },
            set: { viewModel.joinCode = $0 }
        )

        return Form {
            Section("Status") {
                statusView
            }

            Section("Create Session") {
                Button("Create New Session") {
                    viewModel.createSession()
                }
            }

            Section("Join Session") {
                TextField("Enter session code", text: joinCodeBinding)
                    .disableAutocorrection(true)

                Button("Join Session") {
                    viewModel.joinSession()
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 500)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func lobbyView() -> some View {
        VStack(spacing: 0) {
            Form {
                Section("Status") {
                    statusView
                    sessionInfo
                }

                Section("Participants") {
                    participantsList
                }

                Section("Selected Media") {
                    selectedMediaSection
                }

                Section {
                    actionsSection
                }

                Section("Chat") {
                    chatSection
                }
            }
            .formStyle(.grouped)

            if viewModel.isHost {
                startPlaybackButton
                    .padding(16)
            }
        }
    }

    private var statusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch viewModel.connectionState {
            case .connecting:
                Label("Connecting...", systemImage: "wifi")
                    .foregroundStyle(.secondary)
            case .reconnecting:
                Label("Reconnecting...", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .disconnected:
                Label("Disconnected", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(viewModel.code)
                    .font(.title2.weight(.bold))
                    .textSelection(.enabled)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(viewModel.code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var participantsList: some View {
        ForEach(viewModel.participants) { participant in
            HStack(spacing: 10) {
                Text(participant.displayName)
                    .font(.headline)

                if participant.isHost {
                    Text("Host")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.2))
                        )
                }

                Spacer()

                if viewModel.selectedMedia != nil || viewModel.selectedLiveTVChannel != nil {
                    if !participant.hasMediaAccess {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                Image(systemName: participant.isReady ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(participant.isReady ? .green : .secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private var selectedMediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let liveTVChannel = viewModel.selectedLiveTVChannel {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveTVChannel.channelName)
                            .font(.headline)
                        Text("Live TV")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                )
            } else if let selectedMedia = viewModel.selectedMedia {
                HStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedMedia.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(selectedMedia.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.1))
                )
            } else {
                Text("No media selected")
                    .foregroundStyle(.secondary)
            }

            if viewModel.isHost {
                NavigationLink("Select Media") {
                    SearchView(viewModel: SearchViewModel(context: plexApiContext)) { media in
                        viewModel.setSelectedMedia(media)
                    }
                }

                NavigationLink {
                    WatchTogetherLiveTVPickerView { channelId, channelName, thumb in
                        viewModel.setLiveTVChannel(channelId: channelId, channelName: channelName, thumb: thumb)
                    }
                } label: {
                    Label("Live TV Channel", systemImage: "tv")
                }
            }
        }
    }

    private var actionsSection: some View {
        Toggle(
            "Ready",
            isOn: Binding(
                get: { viewModel.readyMap[viewModel.currentParticipantId ?? ""] ?? false },
                set: { _ in viewModel.toggleReady() }
            )
        )
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.chatMessages.isEmpty {
                Text("No messages yet")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(viewModel.chatMessages) { message in
                    chatBubble(message)
                }
            }

            HStack(spacing: 8) {
                TextField("Message...", text: Binding(
                    get: { viewModel.chatInput },
                    set: { viewModel.chatInput = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.sendChatMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(viewModel.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func chatBubble(_ message: WatchTogetherChatMessage) -> some View {
        let isMe = message.senderId == viewModel.currentParticipantId
        return VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
            if !isMe {
                Text(message.senderName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.text)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isMe ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                )
        }
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }

    private var startPlaybackButton: some View {
        VStack(alignment: .center, spacing: 8) {
            Button("Start Playback") {
                viewModel.startPlayback()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canStartPlayback)

            if viewModel.requiresMoreParticipantsToStartPlayback {
                Text("At least 2 participants are required to start playback.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchTogetherLiveTVPickerView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String, String, String?) -> Void

    @State private var viewModel: LiveTVViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading, viewModel.channels.isEmpty {
                    ProgressView("Loading channels...")
                } else {
                    List(viewModel.channels) { channel in
                        Button {
                            onSelect(channel.tuneIdentifier, channel.displayName, channel.thumb)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Text(channel.channelNumber)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)

                                if let thumb = channel.thumb, let thumbURL = URL(string: thumb) {
                                    AsyncImage(url: thumbURL) { phase in
                                        if case let .success(image) = phase {
                                            image.resizable().scaledToFit()
                                        } else {
                                            Color.clear
                                        }
                                    }
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                Text(channel.displayName)
                                    .font(.body)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Select Channel")
        .task {
            if viewModel == nil {
                let vm = LiveTVViewModel(context: plexApiContext)
                vm.settingsManager = settingsManager
                viewModel = vm
                await vm.load()
            }
        }
    }
}
