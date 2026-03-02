import CarPlay

@MainActor
final class CarPlayPlaylistDataSource {
    private let context: PlexAPIContext
    private weak var interfaceController: CPInterfaceController?

    init(context: PlexAPIContext) {
        self.context = context
    }

    func setInterfaceController(_ controller: CPInterfaceController) {
        interfaceController = controller
    }

    // MARK: - Root Template

    func buildRootTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Playlists", sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        loadPlaylists(into: template)
        return template
    }

    // MARK: - Playlist List

    private func loadPlaylists(into template: CPListTemplate) {
        Task {
            do {
                let repo = try PlaylistRepository(context: context)
                let response = try await repo.getAllPlaylists(playlistType: "audio")
                let playlists = response.mediaContainer.metadata ?? []

                let items: [CPListItem] = playlists.map { playlist in
                    let itemCount = playlist.leafCount.map { "\($0) tracks" }
                    let listItem = CPListItem(text: playlist.title, detailText: itemCount)
                    if let thumb = playlist.composite ?? playlist.thumb {
                        CarPlayImageLoader.shared.loadImage(path: thumb, context: context, onto: listItem)
                    }
                    listItem.handler = { [weak self] _, completion in
                        self?.pushPlaylistItems(for: playlist)
                        completion()
                    }
                    return listItem
                }

                template.emptyViewSubtitleVariants = ["No audio playlists"]
                template.updateSections([CPListSection(items: items)])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

    // MARK: - Playlist Items

    private func pushPlaylistItems(for playlist: PlexItem) {
        let template = CPListTemplate(title: playlist.title, sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)

        Task {
            do {
                let repo = try PlaylistRepository(context: context)
                let response = try await repo.getPlaylistItems(ratingKey: playlist.ratingKey)
                let tracks = response.mediaContainer.metadata ?? []

                let playAllItem = CPListItem(text: "Play All", detailText: nil)
                playAllItem.handler = { [weak self] _, completion in
                    self?.playPlaylist(playlist, shuffle: false)
                    completion()
                }

                let shuffleItem = CPListItem(text: "Shuffle", detailText: nil)
                shuffleItem.handler = { [weak self] _, completion in
                    self?.playPlaylist(playlist, shuffle: true)
                    completion()
                }

                let actionSection = CPListSection(
                    items: [playAllItem, shuffleItem],
                    header: nil,
                    sectionIndexTitle: nil
                )

                let trackItems: [CPListItem] = tracks.map { track in
                    let listItem = CPListItem(
                        text: track.title,
                        detailText: track.grandparentTitle
                    )
                    if let thumb = track.thumb ?? track.parentThumb ?? track.grandparentThumb {
                        CarPlayImageLoader.shared.loadImage(path: thumb, context: context, onto: listItem)
                    }
                    listItem.handler = { [weak self] _, completion in
                        self?.playTrackFromPlaylist(track, playlist: playlist)
                        completion()
                    }
                    return listItem
                }

                let trackSection = CPListSection(items: trackItems)
                template.emptyViewSubtitleVariants = ["No tracks"]
                template.updateSections([actionSection, trackSection])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

    // MARK: - Playback

    private func playPlaylist(_ playlist: PlexItem, shuffle: Bool) {
        Task {
            do {
                let queueManager = try PlayQueueManager(context: context)
                let queue = try await queueManager.createQueue(
                    for: playlist.ratingKey,
                    itemType: .playlist,
                    type: "audio",
                    continuous: true,
                    shuffle: shuffle
                )

                guard let firstRatingKey = queue.selectedRatingKey,
                      let firstItem = queue.items.first(where: { $0.ratingKey == firstRatingKey })
                        ?? queue.items.first
                else { return }

                CarPlayNowPlayingManager.shared.play(item: firstItem, queue: queue, context: context)
                interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            } catch {}
        }
    }

    private func playTrackFromPlaylist(_ track: PlexItem, playlist: PlexItem) {
        Task {
            do {
                let queueManager = try PlayQueueManager(context: context)
                let queue = try await queueManager.createQueue(
                    for: track.ratingKey,
                    itemType: .track,
                    type: "audio",
                    continuous: true
                )

                CarPlayNowPlayingManager.shared.play(item: track, queue: queue, context: context)
                interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
            } catch {}
        }
    }
}
