import Foundation
import Observation

@MainActor
@Observable
final class LibraryBrowseViewModel {
    struct SectionCharacter: Identifiable, Hashable {
        let id: String
        let title: String
        let size: Int
        let startIndex: Int
    }

    let library: Library
    var items: [MediaItem] = []
    var sectionCharacters: [SectionCharacter] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    private var reachedEnd = false

    @ObservationIgnored private let context: PlexAPIContext
    private let pageSize = 24

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    func load() async {
        guard items.isEmpty else { return }
        await fetch(reset: true)
        await fetchCharactersIfNeeded()
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false)
    }

    func jump(to character: SectionCharacter) async -> MediaItem? {
        await ensureLoaded(upTo: character.startIndex)
        guard items.indices.contains(character.startIndex) else { return nil }
        return items[character.startIndex]
    }

    private func fetchCharactersIfNeeded() async {
        guard sectionCharacters.isEmpty else { return }
        guard let sectionId = library.sectionId else { return }
        guard let sectionRepository = try? SectionRepository(context: context) else { return }

        do {
            let response = try await sectionRepository.getSectionFirstCharacters(sectionId: sectionId)
            let directories = response.mediaContainer.directory ?? []
            var runningIndex = 0
            var characters: [SectionCharacter] = []

            for directory in directories {
                let size = max(0, directory.size ?? 0)
                guard size > 0 else { continue }
                let title = directory.title ?? directory.key ?? "#"
                let identifier = "\(title)-\(runningIndex)"
                characters.append(
                    SectionCharacter(
                        id: identifier,
                        title: title,
                        size: size,
                        startIndex: runningIndex
                    )
                )
                runningIndex += size
            }

            sectionCharacters = characters
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ensureLoaded(upTo index: Int) async {
        guard index >= 0 else { return }
        while items.count <= index && !reachedEnd {
            await fetch(reset: false)
            if errorMessage != nil {
                break
            }
        }
    }

    private func fetch(reset: Bool) async {
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.browseLibrary"))
            return
        }

        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let start = reset ? 0 : items.count
            let response = try await sectionRepository.getSectionsItems(
                sectionId: sectionId,
                pagination: PlexPagination(start: start, size: pageSize)
            )

            let newItems = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
            let total = response.mediaContainer.totalSize ?? (start + newItems.count)

            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }

            reachedEnd = items.count >= total || newItems.isEmpty
        } catch {
            if reset {
                resetState(error: error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetState(error: String? = nil) {
        items = []
        sectionCharacters = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
    }
}
