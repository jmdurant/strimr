import CarPlay

@MainActor
final class CarPlayMusicDataSource {
    private let context: PlexAPIContext
    private let libraryStore: LibraryStore
    private weak var interfaceController: CPInterfaceController?

    init(context: PlexAPIContext, libraryStore: LibraryStore) {
        self.context = context
        self.libraryStore = libraryStore
    }

    func setInterfaceController(_ controller: CPInterfaceController) {
        interfaceController = controller
    }

    // MARK: - Root Template

    func buildRootTemplate() -> CPListTemplate {
        let musicLibraries = libraryStore.libraries.filter { $0.type == .artist }

        if musicLibraries.count == 1, let library = musicLibraries.first {
            let template = CPListTemplate(title: library.title, sections: [])
            loadArtists(for: library, into: template)
            return template
        }

        let items: [CPListItem] = musicLibraries.map { library in
            let item = CPListItem(text: library.title, detailText: nil)
            item.handler = { [weak self] _, completion in
                self?.pushArtistList(for: library)
                completion()
            }
            return item
        }

        return CPListTemplate(
            title: "Music",
            sections: [CPListSection(items: items)]
        )
    }

    // MARK: - Artist List

    private func pushArtistList(for library: Library) {
        let template = CPListTemplate(title: library.title, sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)
        loadArtists(for: library, into: template)
    }

    private func loadArtists(for library: Library, into template: CPListTemplate) {
        guard let sectionId = library.sectionId else { return }

        Task {
            do {
                let repo = try SectionRepository(context: context)
                let response = try await repo.getSectionsItems(
                    sectionId: sectionId,
                    params: .init(type: "8")
                )

                let items: [CPListItem] = (response.mediaContainer.metadata ?? []).map { artist in
                    let listItem = CPListItem(
                        text: artist.title,
                        detailText: artist.childCount.map { "\($0) albums" }
                    )
                    if let thumb = artist.thumb {
                        CarPlayImageLoader.shared.loadImage(path: thumb, context: context, onto: listItem)
                    }
                    listItem.handler = { [weak self] _, completion in
                        self?.pushAlbumList(for: artist)
                        completion()
                    }
                    return listItem
                }

                template.emptyViewSubtitleVariants = ["No artists found"]
                template.updateSections([CPListSection(items: items)])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

    // MARK: - Album List

    private func pushAlbumList(for artist: PlexItem) {
        let template = CPListTemplate(title: artist.title, sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)

        Task {
            do {
                let repo = try MetadataRepository(context: context)
                let response = try await repo.getMetadataChildren(ratingKey: artist.ratingKey)
                let albums = (response.mediaContainer.metadata ?? []).filter { $0.type == .album }

                let items: [CPListItem] = albums.map { album in
                    let listItem = CPListItem(
                        text: album.title,
                        detailText: album.year.map(String.init)
                    )
                    if let thumb = album.thumb {
                        CarPlayImageLoader.shared.loadImage(path: thumb, context: context, onto: listItem)
                    }
                    listItem.handler = { [weak self] _, completion in
                        self?.pushTrackList(for: album, artistName: artist.title)
                        completion()
                    }
                    return listItem
                }

                template.emptyViewSubtitleVariants = ["No albums found"]
                template.updateSections([CPListSection(items: items)])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

    // MARK: - Track List

    private func pushTrackList(for album: PlexItem, artistName: String) {
        let template = CPListTemplate(title: album.title, sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        interfaceController?.pushTemplate(template, animated: true, completion: nil)

        Task {
            do {
                let repo = try MetadataRepository(context: context)
                let response = try await repo.getMetadataChildren(ratingKey: album.ratingKey)
                let tracks = (response.mediaContainer.metadata ?? []).filter { $0.type == .track }

                let playAllItem = CPListItem(text: "Play All", detailText: nil)
                playAllItem.handler = { [weak self] _, completion in
                    self?.playAlbum(album, shuffle: false)
                    completion()
                }

                let shuffleItem = CPListItem(text: "Shuffle", detailText: nil)
                shuffleItem.handler = { [weak self] _, completion in
                    self?.playAlbum(album, shuffle: true)
                    completion()
                }

                let actionSection = CPListSection(
                    items: [playAllItem, shuffleItem],
                    header: nil,
                    sectionIndexTitle: nil
                )

                let trackItems: [CPListItem] = tracks.map { track in
                    let trackNumber = track.index.map { "\($0). " } ?? ""
                    let listItem = CPListItem(
                        text: "\(trackNumber)\(track.title)",
                        detailText: artistName
                    )
                    listItem.handler = { [weak self] _, completion in
                        self?.playTrack(track)
                        completion()
                    }
                    return listItem
                }

                let trackSection = CPListSection(items: trackItems)
                template.emptyViewSubtitleVariants = ["No tracks found"]
                template.updateSections([actionSection, trackSection])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

    // MARK: - Playback

    private func playAlbum(_ album: PlexItem, shuffle: Bool) {
        Task {
            do {
                let queueManager = try PlayQueueManager(context: context)
                let queue = try await queueManager.createQueue(
                    for: album.ratingKey,
                    itemType: .album,
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

    private func playTrack(_ track: PlexItem) {
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
