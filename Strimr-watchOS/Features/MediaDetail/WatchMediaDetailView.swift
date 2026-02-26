import SwiftUI

struct WatchMediaDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchDownloadManager.self) private var downloadManager

    let media: PlayableMediaItem

    @State private var viewModel: MediaDetailViewModel?
    @State private var presentedPlayQueue: PlayQueueState?

    var body: some View {
        Group {
            if let viewModel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let thumbURL = thumbURL(for: viewModel.media) {
                            PlexAsyncImage(url: thumbURL) {
                                Rectangle()
                                    .fill(.quaternary)
                                    .aspectRatio(16/9, contentMode: .fit)
                            }
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 65)
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

                        if viewModel.media.type == .movie || viewModel.media.type == .episode {
                            downloadButton(ratingKey: viewModel.media.id)
                        } else if viewModel.media.type == .show, let episodeKey = viewModel.primaryActionRatingKey {
                            downloadButton(ratingKey: episodeKey)
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
        .fullScreenCover(item: $presentedPlayQueue) { queue in
            WatchPlayerView(
                playQueue: queue,
                shouldResumeFromOffset: true
            )
            .environment(plexApiContext)
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
            .pickerStyle(.navigationLink)

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

    @ViewBuilder
    private func downloadButton(ratingKey: String) -> some View {
        let status = downloadManager.downloadStatus(for: ratingKey)
        switch status?.status {
        case .downloading:
            HStack(spacing: 6) {
                ProgressView(value: status?.progress ?? 0)
                    .tint(.accentColor)
                Text("\(Int((status?.progress ?? 0) * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .completed:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .queued:
            Label("Queued", systemImage: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Button {
                Task { await downloadManager.enqueueItem(ratingKey: ratingKey, context: plexApiContext) }
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
        case nil:
            Button {
                Task { await downloadManager.enqueueItem(ratingKey: ratingKey, context: plexApiContext) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func play(shouldResume: Bool) async {
        writeDebug("[Detail] play tapped, shouldResume=\(shouldResume), vm=\(viewModel != nil), ratingKey=\(viewModel?.primaryActionRatingKey ?? "NIL"), plexType=\(media.plexType.rawValue)")
        guard let ratingKey = viewModel?.primaryActionRatingKey else {
            writeDebug("[Detail] BAILING: primaryActionRatingKey is nil")
            return
        }
        await launchPlayback(ratingKey: ratingKey, type: media.plexType, shouldResume: shouldResume)
    }

    private func playEpisode(_ episode: MediaItem) async {
        await launchPlayback(ratingKey: episode.id, type: .episode, shouldResume: true)
    }

    private func launchPlayback(ratingKey: String, type: PlexItemType, shouldResume: Bool) async {
        writeDebug("[Detail] launchPlayback ratingKey=\(ratingKey), type=\(type.rawValue)")
        do {
            let manager = try PlayQueueManager(context: plexApiContext)
            let queue = try await manager.createQueue(
                for: ratingKey,
                itemType: type,
                continuous: type == .episode || type == .show || type == .season,
                shuffle: false
            )
            writeDebug("[Detail] queue created, showing player")
            presentedPlayQueue = queue
        } catch {
            writeDebug("[Detail] FAILED to create play queue: \(error)")
            debugPrint("Failed to create play queue:", error)
        }
    }


    private func thumbURL(for media: PlayableMediaItem) -> URL? {
        guard let imageRepository = try? ImageRepository(context: plexApiContext) else { return nil }
        // Prefer landscape backdrop art for the banner, fall back to poster thumb
        if let artPath = media.artPath {
            return imageRepository.transcodeImageURL(path: artPath, width: 200, height: 112)
        }
        let path = media.thumbPath ?? media.parentThumbPath ?? media.grandparentThumbPath
        return path.flatMap { imageRepository.transcodeImageURL(path: $0, width: 400, height: 600) }
    }
}
