import SwiftUI

struct LiveStreamInfo: Identifiable {
    let id = UUID()
    let url: URL
    let channelName: String
}

struct WatchLiveTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    @State private var viewModel: LiveTVViewModel?
    @State private var activeStream: LiveStreamInfo?
    @State private var tuningChannelKey: String?

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
                        ForEach(viewModel.channels) { channel in
                            Button {
                                Task { await tuneChannel(channel) }
                            } label: {
                                channelRow(channel)
                            }
                            .disabled(tuningChannelKey != nil)
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
    }

    @ViewBuilder
    private func channelRow(_ channel: PlexChannel) -> some View {
        HStack(spacing: 8) {
            Text(channel.key)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName)
                    .font(.caption)

                if tuningChannelKey == channel.id {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Tuning...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
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
