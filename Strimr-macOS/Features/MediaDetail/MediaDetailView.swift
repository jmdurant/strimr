import SwiftUI

struct MediaDetailView: View {
    @State var viewModel: MediaDetailViewModel
    let onPlay: (String, PlexItemType) -> Void
    let onPlayFromStart: (String, PlexItemType) -> Void
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                if viewModel.media.type == .show {
                    seasonEpisodesSection
                }

                if !viewModel.cast.isEmpty {
                    castSection
                }

                if !viewModel.relatedHubs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Related")
                            .font(.title2.weight(.bold))
                        ForEach(viewModel.relatedHubs) { hub in
                            MediaHubSection(title: hub.title) {
                                MediaCarousel(layout: .portrait, items: hub.items, showsLabels: true, onSelectMedia: onSelectMedia)
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await viewModel.loadDetails()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 24) {
            posterImage

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.media.title)
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(3)

                metadataRow

                if let summary = viewModel.media.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                }

                if !viewModel.media.genres.isEmpty {
                    Text(viewModel.media.genres.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let heroImageURL = viewModel.heroImageURL {
            AsyncImage(url: heroImageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    posterPlaceholder
                case .failure:
                    posterPlaceholder
                @unknown default:
                    posterPlaceholder
                }
            }
            .frame(width: 220, height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 220, height: 330)
            .overlay(
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.gray.opacity(0.5))
            )
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let year = viewModel.yearText {
                Text(year)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let rating = viewModel.ratingText {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(rating)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let runtime = viewModel.runtimeText {
                Text(runtime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let contentRating = viewModel.media.contentRating {
                Text(contentRating)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let ratingKey = viewModel.primaryActionRatingKey {
                Button {
                    onPlay(ratingKey, viewModel.media.plexType)
                } label: {
                    Label(viewModel.primaryActionTitle, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if viewModel.shouldShowPlayFromStartButton {
                    Button {
                        onPlayFromStart(ratingKey, viewModel.media.plexType)
                    } label: {
                        Label("Play from Start", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var seasonEpisodesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.seasons.isEmpty {
                HStack(spacing: 12) {
                    Text("Seasons")
                        .font(.title2.weight(.bold))

                    Picker("Season", selection: Binding(
                        get: { viewModel.selectedSeasonId ?? "" },
                        set: { newValue in
                            Task { await viewModel.selectSeason(id: newValue) }
                        }
                    )) {
                        ForEach(viewModel.seasons) { season in
                            Text(season.title).tag(season.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
            }

            if viewModel.isLoadingEpisodes {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if !viewModel.episodes.isEmpty {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.episodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: MediaItem) -> some View {
        HStack(spacing: 12) {
            if let imageURL = viewModel.imageURL(for: episode) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 160, height: 90)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let index = episode.index {
                        Text("E\(index)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(episode.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                if let summary = episode.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let runtime = viewModel.runtimeText(for: episode) {
                    Text(runtime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                onPlay(episode.id, episode.type)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.gray.opacity(0.06))
        )
    }

    @ViewBuilder
    private var castSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(.title2.weight(.bold))

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(viewModel.cast) { member in
                        VStack(spacing: 6) {
                            if let imageURL = viewModel.castImageURL(for: member) {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        Circle()
                                            .fill(Color.gray.opacity(0.2))
                                    }
                                }
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(.gray)
                                    )
                            }

                            Text(member.name)
                                .font(.caption)
                                .lineLimit(1)

                            if let character = member.character {
                                Text(character)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 90)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}
