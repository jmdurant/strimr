import SwiftUI

struct LiveTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

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
                    switch viewMode {
                    case .list:
                        channelList(viewModel: viewModel)
                    case .guide:
                        EPGGridView(viewModel: viewModel, onTune: { channel in
                            Task { await tuneChannel(channel) }
                        }, onRecord: { program, channel in
                            programToRecord = program
                            channelToRecord = channel
                        })
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Live TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
        .task {
            if viewModel == nil {
                let vm = LiveTVViewModel(context: plexApiContext)
                vm.settingsManager = settingsManager
                viewModel = vm
                await vm.load()
            }
        }
        .refreshable {
            await viewModel?.reload()
        }
        .fullScreenCover(item: $activeStream) { info in
            LiveTVPlayerView(streamURL: info.url, channelName: info.channelName)
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
                .disabled(tuningChannelKey != nil)
            }
        }
        .listStyle(.plain)
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
    }

    private func tuneChannel(_ channel: PlexChannel) async {
        tuningChannelKey = channel.id
        defer { tuningChannelKey = nil }

        guard let result = await viewModel?.tune(channel: channel) else { return }
        activeStream = LiveStreamInfo(url: result.url, channelName: result.channelName)
    }
}
