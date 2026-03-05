import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
final class LibraryStore {
    var libraries: [Library] = []
    var hasLiveTV = false
    var isLoading = false
    var loadFailed = false

    @ObservationIgnored private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
    }

    func loadLibraries() async throws {
        guard !isLoading else { return }
        guard libraries.isEmpty else { return }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            let repository = try SectionRepository(context: context)
            let response = try await repository.getSections()
            let sections = response.mediaContainer.directory ?? []
            libraries = sections
                .filter(\.type.isSupported)
                .map(Library.init)

            // Check Live TV availability alongside libraries
            await checkLiveTV()

            writeWidgetData()
        } catch {
            loadFailed = true
            throw error
        }
    }

    func reloadLibraries() async throws {
        libraries = []
        hasLiveTV = false
        try await loadLibraries()
    }

    private func writeWidgetData() {
        #if canImport(WidgetKit)
        let items = libraries.map { lib in
            WidgetLibraryItem(
                id: lib.id,
                title: lib.title,
                type: lib.type.rawValue,
                sectionId: lib.sectionId
            )
        }
        let data = WidgetData(
            libraries: items,
            hasLiveTV: hasLiveTV,
            bannerText: "Strimr",
            updatedAt: Date()
        )
        WidgetData.write(data)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func checkLiveTV() async {
        do {
            let repo = try LiveTVRepository(context: context)
            let response = try await repo.getDVRs()
            hasLiveTV = response.mediaContainer.dvr?.isEmpty == false
        } catch {
            hasLiveTV = false
        }
    }
}
