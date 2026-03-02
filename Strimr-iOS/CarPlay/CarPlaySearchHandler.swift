import CarPlay

@MainActor
final class CarPlaySearchHandler: NSObject, CPSearchTemplateDelegate {
    private let context: PlexAPIContext
    private weak var interfaceController: CPInterfaceController?
    private var searchTask: Task<Void, Never>?

    init(context: PlexAPIContext) {
        self.context = context
    }

    func setInterfaceController(_ controller: CPInterfaceController) {
        interfaceController = controller
    }

    func buildSearchTemplate() -> CPSearchTemplate {
        let template = CPSearchTemplate()
        template.delegate = self
        return template
    }

    // MARK: - CPSearchTemplateDelegate

    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        updatedSearchText searchText: String,
        completionHandler: @escaping ([CPListItem]) -> Void
    ) {
        Task { @MainActor in
            searchTask?.cancel()

            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completionHandler([])
                return
            }

            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }

                do {
                    let repo = try SearchRepository(context: context)
                    let response = try await repo.search(params: .init(
                        query: searchText,
                        searchTypes: [.artist, .album, .track],
                        limit: 25
                    ))

                    guard !Task.isCancelled else { return }

                    let results = response.mediaContainer.searchResult ?? []
                    let items: [CPListItem] = results.compactMap { result in
                        guard let metadata = result.metadata else { return nil }

                        let detailText: String? = switch metadata.type {
                        case .artist:
                            "Artist"
                        case .album:
                            [metadata.parentTitle, metadata.year.map(String.init)]
                                .compactMap { $0 }.joined(separator: " · ")
                        case .track:
                            [metadata.grandparentTitle, metadata.parentTitle]
                                .compactMap { $0 }.joined(separator: " — ")
                        default:
                            metadata.type.rawValue.capitalized
                        }

                        let listItem = CPListItem(text: metadata.title, detailText: detailText)
                        let thumb = metadata.thumb ?? metadata.parentThumb ?? metadata.grandparentThumb
                        if let thumb {
                            CarPlayImageLoader.shared.loadImage(path: thumb, context: context, onto: listItem)
                        }
                        listItem.userInfo = metadata
                        listItem.handler = { [weak self] item, completion in
                            if let plexItem = item.userInfo as? PlexItem {
                                self?.handleResultTap(plexItem)
                            }
                            completion()
                        }
                        return listItem
                    }

                    completionHandler(items)
                } catch {
                    completionHandler([])
                }
            }
        }
    }

    nonisolated func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {}

    nonisolated func searchTemplate(
        _ searchTemplate: CPSearchTemplate,
        selectedResult item: CPListItem,
        completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if let plexItem = item.userInfo as? PlexItem {
                handleResultTap(plexItem)
            }
            completionHandler()
        }
    }

    // MARK: - Result Handling

    private func handleResultTap(_ item: PlexItem) {
        switch item.type {
        case .artist:
            pushArtistAlbums(item)
        case .album:
            pushAlbumTracks(item)
        case .track:
            playTrack(item)
        default:
            break
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
