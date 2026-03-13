import CarPlay

@MainActor
final class CarPlayTabBuilder {
    private let context: PlexAPIContext
    private let libraryStore: LibraryStore

    private var musicDataSource: CarPlayMusicDataSource?
    private var playlistDataSource: CarPlayPlaylistDataSource?
    private var recentDataSource: CarPlayRecentDataSource?
    private var searchHandler: CarPlaySearchHandler?

    init(context: PlexAPIContext, libraryStore: LibraryStore) {
        self.context = context
        self.libraryStore = libraryStore
    }

    func buildTabBar(interfaceController: CPInterfaceController) -> CPTabBarTemplate {
        let music = buildMusicTab(interfaceController: interfaceController)
        let playlists = buildPlaylistsTab(interfaceController: interfaceController)
        let recent = buildRecentTab(interfaceController: interfaceController)
        let search = buildSearchTab(interfaceController: interfaceController)

        return CPTabBarTemplate(templates: [music, playlists, recent, search])
    }

    private func buildMusicTab(interfaceController: CPInterfaceController) -> CPListTemplate {
        let dataSource = CarPlayMusicDataSource(context: context, libraryStore: libraryStore)
        dataSource.setInterfaceController(interfaceController)
        musicDataSource = dataSource

        let template = dataSource.buildRootTemplate()
        template.tabImage = UIImage(systemName: "music.note")
        return template
    }

    private func buildPlaylistsTab(interfaceController: CPInterfaceController) -> CPListTemplate {
        let dataSource = CarPlayPlaylistDataSource(context: context)
        dataSource.setInterfaceController(interfaceController)
        playlistDataSource = dataSource

        let template = dataSource.buildRootTemplate()
        template.tabImage = UIImage(systemName: "music.note.list")
        return template
    }

    private func buildRecentTab(interfaceController: CPInterfaceController) -> CPListTemplate {
        let dataSource = CarPlayRecentDataSource(context: context, libraryStore: libraryStore)
        dataSource.setInterfaceController(interfaceController)
        recentDataSource = dataSource

        let template = dataSource.buildRootTemplate()
        template.tabImage = UIImage(systemName: "clock")
        return template
    }

    private func buildSearchTab(interfaceController: CPInterfaceController) -> CPSearchTemplate {
        let handler = CarPlaySearchHandler(context: context)
        handler.setInterfaceController(interfaceController)
        searchHandler = handler

        let template = handler.buildSearchTemplate()
        template.tabImage = UIImage(systemName: "magnifyingglass")
        return template
    }
}
