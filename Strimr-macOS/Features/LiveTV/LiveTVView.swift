import SwiftUI

struct LiveTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager

    @State private var viewModel: LiveTVViewModel?
    @State private var tuningChannelKey: String?
    @State private var programToRecord: EPGGridProgram?
    @State private var channelToRecord: PlexChannel?
    @State private var recordingSuccess = false

    let onTune: (URL, String, String?, Date?) -> Void

    init(onTune: @escaping (URL, String, String?, Date?) -> Void = { _, _, _, _ in }) {
        self.onTune = onTune
    }

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading, viewModel.channels.isEmpty {
                    ProgressView("Loading channels...")
                } else if let errorMessage = viewModel.errorMessage, viewModel.channels.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "tv",
                        description: Text("Check that your server has a DVR configured.")
                    )
                } else {
                    channelList(viewModel: viewModel)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Live TV")
        .task {
            if viewModel == nil {
                let vm = LiveTVViewModel(context: plexApiContext)
                vm.settingsManager = settingsManager
                viewModel = vm
                await vm.load()
            }
        }
        .alert("Unable to Tune", isPresented: Binding(
            get: { viewModel?.tuneError != nil },
            set: { if !$0 { viewModel?.tuneError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.tuneError ?? "")
        }
        .alert(
            "Record \(programToRecord?.title ?? "Program")?",
            isPresented: Binding(
                get: { programToRecord != nil },
                set: { if !$0 { programToRecord = nil; channelToRecord = nil } }
            )
        ) {
            Button("Record") {
                guard let program = programToRecord else { return }
                Task {
                    let success = await viewModel?.scheduleRecording(program: program) ?? false
                    recordingSuccess = success
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let channel = channelToRecord {
                Text("Schedule a DVR recording on \(channel.displayName)?")
            }
        }
        .alert("Recording Scheduled", isPresented: $recordingSuccess) {
            Button("OK", role: .cancel) {}
        }
        .alert("Recording Failed", isPresented: Binding(
            get: { viewModel?.recordingError != nil },
            set: { if !$0 { viewModel?.recordingError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.recordingError ?? "")
        }
    }

    private var favoritesSorted: [PlexChannel] {
        let favoriteIds = Set(settingsManager.interface.favoriteChannelIds)
        guard let viewModel, !favoriteIds.isEmpty else { return viewModel?.channels ?? [] }
        let favorites = viewModel.channels.filter { favoriteIds.contains($0.id) }
        let rest = viewModel.channels.filter { !favoriteIds.contains($0.id) }
        return favorites + rest
    }

    @ViewBuilder
    private func channelList(viewModel: LiveTVViewModel) -> some View {
        List {
            ForEach(favoritesSorted) { channel in
                Button {
                    Task { await tuneChannel(channel) }
                } label: {
                    channelRow(channel)
                }
                .buttonStyle(.plain)
                .disabled(tuningChannelKey != nil)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func channelRow(_ channel: PlexChannel) -> some View {
        HStack(spacing: 12) {
            Text(channel.channelNumber)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()

            if let thumb = channel.thumb, let thumbURL = URL(string: thumb) {
                AsyncImage(url: thumbURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        Color.clear
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName)
                    .font(.body)
                    .lineLimit(1)

                if tuningChannelKey == channel.id {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Tuning...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let np = viewModel?.nowPlaying(for: channel) {
                    HStack(spacing: 4) {
                        Text(np.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let remaining = np.timeRemaining {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(remaining)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Spacer()

            Button {
                settingsManager.toggleFavoriteChannel(channel.id)
            } label: {
                Image(systemName: settingsManager.interface.favoriteChannelIds.contains(channel.id) ? "star.fill" : "star")
                    .font(.body)
                    .foregroundStyle(settingsManager.interface.favoriteChannelIds.contains(channel.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private func tuneChannel(_ channel: PlexChannel) async {
        tuningChannelKey = channel.id
        defer { tuningChannelKey = nil }

        guard let result = await viewModel?.tune(channel: channel) else { return }
        let airing = viewModel?.airingProgram(for: channel)
        let np = viewModel?.nowPlaying(for: channel)
        let title = result.programTitle ?? airing?.title ?? np?.title
        let endsAt = airing?.endsAt ?? np?.endsAt
        onTune(result.url, result.channelName, title, endsAt)
    }
}
