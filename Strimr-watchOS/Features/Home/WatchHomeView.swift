import SwiftUI

struct WatchHomeView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchDownloadManager.self) private var downloadManager

    @State var viewModel: HomeViewModel

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
        .navigationDestination(for: PlayableMediaItem.self) { media in
            WatchMediaDetailView(media: media)
        }
        .navigationTitle("Home")
        .task {
            guard !isOffline else { return }
            await viewModel.load()
        }
        .onAppear {
            guard !isOffline else { return }
            if viewModel.hasContent {
                Task { await viewModel.reload() }
            }
        }
        .refreshable {
            guard !isOffline else { return }
            await viewModel.reload()
        }
    }

    // MARK: - Online

    private var onlineContent: some View {
        Group {
            if viewModel.isLoading && !viewModel.hasContent {
                ProgressView()
            } else if let errorMessage = viewModel.errorMessage, !viewModel.hasContent {
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                List {
                    if let continueWatching = viewModel.continueWatching, continueWatching.hasItems {
                        Section("Continue Watching") {
                            ForEach(continueWatching.items.prefix(3)) { item in
                                WatchMediaRow(item: item)
                            }
                        }
                    }

                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            Section(hub.title) {
                                ForEach(hub.items.prefix(3)) { item in
                                    WatchMediaRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Offline

    private var completedDownloads: [DownloadItem] {
        downloadManager.items.filter { $0.status == .completed }
    }

    @ViewBuilder
    private var offlineContent: some View {
        if completedDownloads.isEmpty {
            ContentUnavailableView(
                "No Downloads",
                systemImage: "arrow.down.circle",
                description: Text("Download content to view it offline.")
            )
        } else {
            offlineList
        }
    }

    @State private var selectedOfflineItem: DownloadItem?

    private func mostRecentlyPlayed(_ items: [DownloadItem]) -> DownloadItem? {
        items
            .filter { $0.metadata.lastViewedAt != nil }
            .max { ($0.metadata.lastViewedAt ?? .distantPast) < ($1.metadata.lastViewedAt ?? .distantPast) }
            ?? items.first
    }

    private var offlineList: some View {
        let movies = completedDownloads.filter { $0.metadata.type == .movie }
        let episodes = completedDownloads.filter { $0.metadata.type == .episode }
        let tracks = completedDownloads.filter { $0.metadata.type == .track }

        let showsByName = Dictionary(grouping: episodes) { $0.metadata.grandparentTitle ?? "Unknown Show" }

        return List {
            if let movie = mostRecentlyPlayed(movies) {
                Section("Movies") {
                    Button { selectedOfflineItem = movie } label: {
                        WatchOfflineMediaRow(item: movie)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(showsByName.keys.sorted(), id: \.self) { showName in
                if let episode = mostRecentlyPlayed(showsByName[showName] ?? []) {
                    Section(showName) {
                        Button { selectedOfflineItem = episode } label: {
                            WatchOfflineMediaRow(item: episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let track = mostRecentlyPlayed(tracks) {
                Section("Music") {
                    Button { selectedOfflineItem = track } label: {
                        WatchOfflineMediaRow(item: track)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(item: $selectedOfflineItem) { item in
            DownloadPlayerLauncher(item: item)
        }
    }
}
