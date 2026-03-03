import SwiftUI

struct LiveTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: LiveTVViewModel?
    @State private var activeStream: LiveStreamInfo?
    @State private var tuningChannelKey: String?

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
        .navigationBarTitleDisplayMode(.inline)
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
            LiveTVPlayerView(streamURL: info.url, channelName: info.channelName)
        }
    }

    @ViewBuilder
    private func channelList(viewModel: LiveTVViewModel) -> some View {
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
        .listStyle(.plain)
    }

    @ViewBuilder
    private func channelRow(_ channel: PlexChannel) -> some View {
        HStack(spacing: 12) {
            Text(channel.key)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()

            if let thumb = channel.thumb,
               let baseURL = plexApiContext.baseURLServer,
               let token = plexApiContext.authTokenServer {
                let thumbURL = baseURL.appendingPathComponent(thumb)
                    .appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: token)])
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
