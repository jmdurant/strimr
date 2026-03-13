import CarPlay

@MainActor
final class CarPlayRecentDataSource {
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
        let template = CPListTemplate(title: "Recent", sections: [])
        template.emptyViewSubtitleVariants = ["Loading..."]
        loadRecentHubs(into: template)
        return template
    }

    // MARK: - Load Hubs

    private func loadRecentHubs(into template: CPListTemplate) {
        let musicLibraries = libraryStore.libraries.filter { $0.type == .artist }

        Task {
            var allSections: [CPListSection] = []

            for library in musicLibraries {
                guard let sectionId = library.sectionId else { continue }

                do {
                    let repo = try HubRepository(context: context)
                    let response = try await repo.getSectionHubs(sectionId: sectionId)
                    let hubs = response.mediaContainer.hub ?? []

                    for hub in hubs {
                        guard let metadata = hub.metadata, !metadata.isEmpty else { continue }

                        let items: [CPListItem] = metadata.prefix(10).map { item in
                            let detailText: String? = switch item.type {
                            case .album:
                                item.parentTitle ?? item.year.map(String.init)
                            case .track:
                                item.grandparentTitle
                            case .artist:
                                item.childCount.map { "\($0) albums" }
                            default:
                                item.year.map(String.init)
                            }

                            let listItem = CPListItem(text: item.title, detailText: detailText)
                            let thumb = item.thumb ?? item.parentThumb ?? item.grandparentThumb
                            if let thumb {
                                CarPlayImageLoader.shared.loadImage(path: thumb, context: context, onto: listItem)
                            }
                            listItem.handler = { [weak self] _, completion in
                                self?.handleItemTap(item)
                                completion()
                            }
                            return listItem
                        }

                        let headerTitle = musicLibraries.count > 1
                            ? "\(library.title) — \(hub.title)"
                            : hub.title
                        allSections.append(CPListSection(
                            items: items,
                            header: headerTitle,
                            sectionIndexTitle: nil
                        ))
                    }
                } catch {}
            }

            template.emptyViewSubtitleVariants = ["No recent music"]
            template.updateSections(allSections)
        }
    }

    // MARK: - Item Tap

    private func handleItemTap(_ item: PlexItem) {
        switch item.type {
        case .track:
            playTrack(item)
        case .album:
            pushAlbumTracks(item)
        case .artist:
            pushArtistAlbums(item)
        default:
            playTrack(item)
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

    private func pushAlbumTracks(_ album: PlexItem) {
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

                let trackItems: [CPListItem] = tracks.map { track in
                    let trackNumber = track.index.map { "\($0). " } ?? ""
                    let listItem = CPListItem(
                        text: "\(trackNumber)\(track.title)",
                        detailText: track.grandparentTitle
                    )
                    listItem.handler = { [weak self] _, completion in
                        self?.playTrack(track)
                        completion()
                    }
                    return listItem
                }

                template.emptyViewSubtitleVariants = ["No tracks"]
                template.updateSections([
                    CPListSection(items: [playAllItem, shuffleItem]),
                    CPListSection(items: trackItems),
                ])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

    private func pushArtistAlbums(_ artist: PlexItem) {
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
                        self?.pushAlbumTracks(album)
                        completion()
                    }
                    return listItem
                }

                template.emptyViewSubtitleVariants = ["No albums"]
                template.updateSections([CPListSection(items: items)])
            } catch {
                template.emptyViewSubtitleVariants = ["Failed to load"]
            }
        }
    }

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
}
