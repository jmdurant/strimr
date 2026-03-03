import SwiftUI

struct LiveTVTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    @State private var viewModel: LiveTVViewModel?
    @State private var activeStream: LiveStreamInfo?
    @State private var tuningChannelKey: String?

    private let gridColumns = [
        GridItem(.flexible(minimum: 200), spacing: 48),
        GridItem(.flexible(minimum: 200), spacing: 48),
        GridItem(.flexible(minimum: 200), spacing: 48),
    ]

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
                    channelGrid(viewModel: viewModel)
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
        .fullScreenCover(item: $activeStream) { info in
            LiveTVPlayerTVView(streamURL: info.url, channelName: info.channelName)
        }
    }

    @ViewBuilder
    private func channelGrid(viewModel: LiveTVViewModel) -> some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 48) {
                ForEach(viewModel.channels) { channel in
                    Button {
                        Task { await tuneChannel(channel) }
                    } label: {
                        channelCard(channel)
                    }
                    .buttonStyle(.plain)
                    .disabled(tuningChannelKey != nil)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 32)
        }
    }

    @ViewBuilder
    private func channelCard(_ channel: PlexChannel) -> some View {
        VStack(spacing: 12) {
            ZStack {
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
            }

            VStack(spacing: 4) {
                Text(channel.key)
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
