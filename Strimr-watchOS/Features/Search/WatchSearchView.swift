import SwiftUI

struct WatchSearchView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchDownloadManager.self) private var downloadManager

    @State private var viewModel: SearchViewModel?
    @State private var offlineQuery = ""
    @State private var selectedOfflineItem: DownloadItem?

    private var isOffline: Bool {
        settingsManager.settings.interface.offlineMode
    }

    var body: some View {
        Group {
            if isOffline {
                offlineContent
            } else {
                onlineContent
            }
        }
        .navigationTitle("Search")
        .task {
            guard !isOffline else { return }
            viewModel = SearchViewModel(context: plexApiContext)
        }
    }

    // MARK: - Online

    @ViewBuilder
    private var onlineContent: some View {
        if let viewModel {
            @Bindable var vm = viewModel
            List {
                if viewModel.isLoading {
                    ProgressView()
                } else if !viewModel.hasQuery {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text("Search your Plex library.")
                    )
                } else if viewModel.filteredItems.isEmpty {
                    ContentUnavailableView.search(text: viewModel.query)
                } else {
                    ForEach(viewModel.filteredItems) { item in
                        WatchMediaRow(item: item)
                    }
                }
            }
            .navigationDestination(for: PlayableMediaItem.self) { media in
                WatchMediaDetailView(media: media)
            }
            .searchable(text: $vm.query, prompt: "Search")
            .onSubmit(of: .search) {
                viewModel.submitSearch()
            }
            .onChange(of: viewModel.query) {
                viewModel.queryDidChange()
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Offline

    private var offlineResults: [DownloadItem] {
        let query = offlineQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        let completed = downloadManager.items.filter { $0.status == .completed }
        return completed.filter {
            $0.metadata.title.lowercased().contains(query)
                || ($0.metadata.grandparentTitle?.lowercased().contains(query) ?? false)
                || ($0.metadata.parentTitle?.lowercased().contains(query) ?? false)
        }
    }

    private var hasQuery: Bool {
        !offlineQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var offlineContent: some View {
        List {
            if !hasQuery {
                ContentUnavailableView(
                    "Search Downloads",
                    systemImage: "magnifyingglass",
                    description: Text("Type to search your downloaded content.")
                )
            } else if offlineResults.isEmpty {
                ContentUnavailableView.search(text: offlineQuery)
            } else {
                ForEach(offlineResults) { item in
                    Button { selectedOfflineItem = item } label: {
                        WatchOfflineMediaRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $offlineQuery, prompt: "Search Downloads")
        .navigationDestination(item: $selectedOfflineItem) { item in
            DownloadPlayerLauncher(item: item)
        }
    }
}
