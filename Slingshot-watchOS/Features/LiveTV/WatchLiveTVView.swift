import SwiftUI

struct WatchLiveTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager

    @State private var viewModel: LiveTVViewModel?
    @State private var activeStream: LiveStreamInfo?
    @State private var tuningChannelKey: String?

    private var favoritesSorted: [PlexChannel] {
        let favoriteIds = Set(settingsManager.interface.favoriteChannelIds)
        guard let viewModel, !favoriteIds.isEmpty else { return viewModel?.channels ?? [] }
        let favorites = viewModel.channels.filter { favoriteIds.contains($0.id) }
        let rest = viewModel.channels.filter { !favoriteIds.contains($0.id) }
        return favorites + rest
    }

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading {
                    ProgressView("Loading channels...")
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "tv")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(favoritesSorted) { channel in
                            Button {
                                Task { await tuneChannel(channel) }
                            } label: {
                                channelRow(channel)
                            }
                            .disabled(tuningChannelKey != nil)
                            .swipeActions(edge: .leading) {
                                let isFav = settingsManager.interface.favoriteChannelIds.contains(channel.id)
                                Button {
                                    settingsManager.toggleFavoriteChannel(channel.id)
                                } label: {
                                    Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star.fill")
                                }
                                .tint(.yellow)
                            }
                        }
                    }
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
        .refreshable {
            await viewModel?.reload()
        }
        .fullScreenCover(item: $activeStream) { info in
            WatchLivePlayerView(streamURL: info.url, channelName: info.channelName)
                .environment(plexApiContext)
        }
        .alert("Unable to Tune", isPresented: Binding(
            get: { viewModel?.tuneError != nil },
            set: { if !$0 { viewModel?.tuneError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel?.tuneError ?? "")
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: PlexChannel) -> some View {
        HStack(spacing: 8) {
            Text(channel.channelNumber)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(channel.displayName)
                        .font(.caption)
                    if settingsManager.interface.favoriteChannelIds.contains(channel.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                }

                if tuningChannelKey == channel.id {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Tuning...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let np = viewModel?.nowPlaying(for: channel) {
                    Text(np.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func tuneChannel(_ channel: PlexChannel) async {
        tuningChannelKey = channel.id
        defer { tuningChannelKey = nil }

        guard let result = await viewModel?.tune(channel: channel) else { return }
        activeStream = LiveStreamInfo(url: result.url, channelName: result.channelName)
    }
}
