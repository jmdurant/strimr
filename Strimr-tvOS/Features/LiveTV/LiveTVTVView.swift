import SwiftUI

struct LiveTVTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager

    @State private var viewModel: LiveTVViewModel?
    @State private var activeStream: LiveStreamInfo?
    @State private var tuningChannelKey: String?
    @State private var viewMode: ViewMode = .list
    @State private var programToRecord: EPGGridProgram?
    @State private var channelToRecord: PlexChannel?
    @State private var recordingSuccess = false

    private enum ViewMode: String, CaseIterable {
        case list = "List"
        case guide = "Guide"
    }

    private let gridColumns = [
        GridItem(.flexible(minimum: 200), spacing: 48),
        GridItem(.flexible(minimum: 200), spacing: 48),
        GridItem(.flexible(minimum: 200), spacing: 48),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .padding(.bottom, 24)

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
                        switch viewMode {
                        case .list:
                            channelGrid(viewModel: viewModel)
                        case .guide:
                            EPGGridView(viewModel: viewModel, onTune: { channel in
                                Task { await tuneChannel(channel) }
                            }, onRecord: { program, channel in
                                programToRecord = program
                                channelToRecord = channel
                            })
                            .focusSection()
                        }
                    }
                } else {
                    ProgressView()
                }
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
        .fullScreenCover(item: $activeStream) { info in
            LiveTVPlayerTVView(streamURL: info.url, channelName: info.channelName)
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
    private func channelGrid(viewModel: LiveTVViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 48) {
                ForEach(favoritesSorted) { channel in
                    Button {
                        Task { await tuneChannel(channel) }
                    } label: {
                        channelCard(channel)
                    }
                    .buttonStyle(.plain)
                    .disabled(tuningChannelKey != nil)
                    .contextMenu {
                        let isFav = settingsManager.interface.favoriteChannelIds.contains(channel.id)
                        Button {
                            settingsManager.toggleFavoriteChannel(channel.id)
                        } label: {
                            Label(isFav ? "Remove Favorite" : "Add to Favorites", systemImage: isFav ? "star.slash" : "star.fill")
                        }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
    }

    @ViewBuilder
    private func channelCard(_ channel: PlexChannel) -> some View {
        let isFav = settingsManager.interface.favoriteChannelIds.contains(channel.id)
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: 140)

                if tuningChannelKey == channel.id {
                    ProgressView()
                } else {
                    Image(systemName: "tv")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                }

                if isFav {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(8)
                }
            }

            VStack(spacing: 4) {
                Text(channel.channelNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(channel.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if let np = viewModel?.nowPlaying(for: channel) {
                    Text(np.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if let remaining = np.timeRemaining {
                        Text(remaining)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    private func tuneChannel(_ channel: PlexChannel) async {
        tuningChannelKey = channel.id
        defer { tuningChannelKey = nil }

        guard let result = await viewModel?.tune(channel: channel) else { return }
        activeStream = LiveStreamInfo(url: result.url, channelName: result.channelName)
    }
}
