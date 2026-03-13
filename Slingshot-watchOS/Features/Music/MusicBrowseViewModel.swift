import Foundation
import Observation

@MainActor @Observable
final class MusicBrowseViewModel {
    enum Level {
        case artists(sectionId: Int)
        case albums(artistKey: String)
        case tracks(albumKey: String)
    }

    private(set) var items: [MediaItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var reachedEnd = false

    let level: Level
    private let context: PlexAPIContext

    init(level: Level, context: PlexAPIContext) {
        self.level = level
        self.context = context
    }

    func load() async {
        guard items.isEmpty else { return }
        await fetch(reset: true)
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let newItems: [MediaItem]
            let total: Int

            switch level {
            case let .artists(sectionId):
                let repo = try SectionRepository(context: context)
                let start = reset ? 0 : items.count
                let response = try await repo.getSectionsItems(
                    sectionId: sectionId,
                    params: SectionRepository.SectionItemsParams(type: "8"),
                    pagination: PlexPagination(start: start, size: 50)
                )
                newItems = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
                total = response.mediaContainer.totalSize ?? (start + newItems.count)

            case let .albums(artistKey):
                let repo = try MetadataRepository(context: context)
                let response = try await repo.getMetadataChildren(ratingKey: artistKey)
                newItems = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
                total = newItems.count
                reachedEnd = true

            case let .tracks(albumKey):
                let repo = try MetadataRepository(context: context)
                let response = try await repo.getMetadataChildren(ratingKey: albumKey)
                newItems = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
                total = newItems.count
                reachedEnd = true
            }

            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }

            if !reachedEnd {
                reachedEnd = items.count >= total || newItems.isEmpty
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}
