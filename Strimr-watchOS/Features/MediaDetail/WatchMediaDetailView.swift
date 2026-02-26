import SwiftUI

struct WatchMediaDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager

    let media: PlayableMediaItem

    @State private var viewModel: MediaDetailViewModel?
    @State private var isShowingPlayer = false
    @State private var playQueue: PlayQueueState?

    var body: some View {
        Group {
            if let viewModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let thumbURL = thumbURL(for: viewModel.media) {
                            AsyncImage(url: thumbURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(.quaternary)
                                    .aspectRatio(2/3, contentMode: .fit)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                            .clipped()
                            .cornerRadius(8)
                        }

                        Text(viewModel.media.primaryLabel)
                            .font(.headline)

                        HStack(spacing: 4) {
                            if let year = viewModel.yearText {
                                Text(year)
                            }
                            if let runtime = viewModel.runtimeText {
                                Text(runtime)
                            }
                            if let rating = viewModel.ratingText {
                                Text(rating)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        Button {
                            Task { await play(shouldResume: true) }
                        } label: {
                            Label(viewModel.primaryActionTitle, systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }

                        if viewModel.shouldShowPlayFromStartButton {
                            Button {
                                Task { await play(shouldResume: false) }
                            } label: {
                                Label("Play from Start", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        if let summary = viewModel.media.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }

                        if viewModel.media.type == .show {
                            seasonSection(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(media.title)
        .task {
            let vm = MediaDetailViewModel(media: media, context: plexApiContext)
            viewModel = vm
            await vm.loadDetails()
        }
        .fullScreenCover(isPresented: $isShowingPlayer) {
            if let playQueue {
                WatchPlayerView(
                    playQueue: playQueue,
                    shouldResumeFromOffset: true
                )
            }
        }
    }

    @ViewBuilder
    private func seasonSection(viewModel: MediaDetailViewModel) -> some View {
        if !viewModel.seasons.isEmpty {
            Picker("Season", selection: Binding(
                get: { viewModel.selectedSeasonId ?? "" },
                set: { id in Task { await viewModel.selectSeason(id: id) } }
            )) {
                ForEach(viewModel.seasons) { season in
                    Text(season.title).tag(season.id)
                }
            }

            if viewModel.isLoadingEpisodes {
                ProgressView()
            } else {
                ForEach(viewModel.episodes) { episode in
                    Button {
                        Task { await playEpisode(episode) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let label = episode.tertiaryLabel {
                                Text(label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(episode.title)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func play(shouldResume: Bool) async {
        guard let ratingKey = viewModel?.primaryActionRatingKey else { return }
        await launchPlayback(ratingKey: ratingKey, type: media.plexType, shouldResume: shouldResume)
    }

    private func playEpisode(_ episode: MediaItem) async {
        await launchPlayback(ratingKey: episode.id, type: .episode, shouldResume: true)
    }

    private func launchPlayback(ratingKey: String, type: PlexItemType, shouldResume: Bool) async {
        do {
            let manager = try PlayQueueManager(context: plexApiContext)
            let queue = try await manager.createQueue(
                for: ratingKey,
                itemType: type,
                continuous: type == .episode || type == .show || type == .season,
                shuffle: false
            )
            playQueue = queue
            isShowingPlayer = true
        } catch {
            debugPrint("Failed to create play queue:", error)
        }
    }

    private func thumbURL(for media: PlayableMediaItem) -> URL? {
        guard let imageRepository = try? ImageRepository(context: plexApiContext) else { return nil }
        let path = media.thumbPath ?? media.parentThumbPath ?? media.grandparentThumbPath
        return path.flatMap { imageRepository.transcodeImageURL(path: $0, width: 400, height: 600) }
    }
}
