import SwiftUI

struct PlaylistDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @State var viewModel: PlaylistDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void
    let onShuffle: (String) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    init(
        viewModel: PlaylistDetailViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onPlay: @escaping (String) -> Void = { _ in },
        onShuffle: @escaping (String) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlay = onPlay
        self.onShuffle = onShuffle
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                actionButtons

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(viewModel.items) { media in
                        PortraitMediaCard(media: media, width: 150, showsLabels: true) {
                            onSelectMedia(media)
                        }
                    }
                }
            }
            .padding(24)
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView("Loading...")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "No items",
                    systemImage: "square.grid.2x2.fill"
                )
            }
        }
        .navigationTitle(viewModel.playlist.title)
        .task {
            await viewModel.load()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 20) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: .thumb,
                    media: viewModel.playlistDisplayItem
                )
            )
            .frame(width: 160, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.playlist.title)
                    .font(.title.bold())

                if let count = viewModel.elementsCountText {
                    Text(count)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let duration = viewModel.durationText {
                    Text(duration)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let summary = viewModel.playlist.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                onPlay(viewModel.playlist.id)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                onShuffle(viewModel.playlist.id)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
