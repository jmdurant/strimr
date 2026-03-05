import AppIntents

// MARK: - Entity for Libraries

struct LibraryEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Library")
    static var defaultQuery = LibraryQuery()

    var id: String
    var title: String
    var iconName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: iconName))
    }
}

struct LibraryQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [LibraryEntity] {
        let store = AppDependencies.shared.libraryStore
        if store.libraries.isEmpty {
            try? await store.loadLibraries()
        }
        return store.libraries
            .filter { identifiers.contains($0.id) }
            .map { LibraryEntity(id: $0.id, title: $0.title, iconName: $0.iconName) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LibraryEntity] {
        let store = AppDependencies.shared.libraryStore
        if store.libraries.isEmpty {
            try? await store.loadLibraries()
        }
        return store.libraries
            .map { LibraryEntity(id: $0.id, title: $0.title, iconName: $0.iconName) }
    }
}

// MARK: - Open Library

struct OpenLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Library"
    static var description: IntentDescription = "Opens a Plex library in Strimr"
    static var openAppWhenRun = true

    @Parameter(title: "Library")
    var library: LibraryEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = AppDependencies.shared.libraryStore
        if store.libraries.isEmpty {
            try? await store.loadLibraries()
        }
        if let lib = store.libraries.first(where: { $0.id == library.id }) {
            NotificationCenter.default.post(
                name: .siriOpenLibrary,
                object: nil,
                userInfo: ["library": lib]
            )
        }
        return .result()
    }
}

// MARK: - Resume Playback

struct ResumePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Playback"
    static var description: IntentDescription = "Resumes the current media playback"
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveActivityManager.shared.activePlayerCoordinator?.resume()
        return .result()
    }
}

// MARK: - Pause Playback

struct PausePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Playback"
    static var description: IntentDescription = "Pauses the current media playback"

    @MainActor
    func perform() async throws -> some IntentResult {
        LiveActivityManager.shared.activePlayerCoordinator?.pause()
        return .result()
    }
}

// MARK: - Shuffle Library

struct ShuffleLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Shuffle Library"
    static var description: IntentDescription = "Shuffles and plays a Plex library"
    static var openAppWhenRun = true

    @Parameter(title: "Library")
    var library: LibraryEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        let store = deps.libraryStore
        if store.libraries.isEmpty {
            try? await store.loadLibraries()
        }

        guard let lib = store.libraries.first(where: { $0.id == library.id }),
              let sectionId = lib.sectionId
        else { return .result() }

        // Fetch a random item from the library and start a shuffled queue
        let sectionRepo = try SectionRepository(context: deps.plexApiContext)
        let container = try await sectionRepo.getSectionsItems(
            sectionId: sectionId,
            params: SectionRepository.SectionItemsParams(
                sort: "random",
                limit: 1,
                type: lib.type == .artist ? "10" : nil
            ),
            pagination: PlexPagination(start: 0, size: 1),
        )

        guard let item = container.mediaContainer.metadata?.first
        else { return .result() }

        let ratingKey = item.ratingKey
        let manager = try PlayQueueManager(context: deps.plexApiContext)
        let itemType = item.type
        let playQueue = try await manager.createQueue(
            for: ratingKey,
            itemType: itemType,
            type: itemType.isAudio ? "audio" : "video",
            continuous: true,
            shuffle: true,
        )

        NotificationCenter.default.post(
            name: .siriPlayQueue,
            object: nil,
            userInfo: ["playQueue": playQueue]
        )

        return .result()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let siriOpenLibrary = Notification.Name("strimr.siri.openLibrary")
    static let siriPlayQueue = Notification.Name("strimr.siri.playQueue")
}
