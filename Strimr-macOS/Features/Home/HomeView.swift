import SwiftUI

@MainActor
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onSelectLibrary: (Library) -> Void
    let onSelectLiveTV: () -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onSelectLibrary: @escaping (Library) -> Void = { _ in },
        onSelectLiveTV: @escaping () -> Void = {}
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onSelectLibrary = onSelectLibrary
        self.onSelectLiveTV = onSelectLiveTV
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        MediaCarousel(
                            layout: .landscape,
                            items: hub.items,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia
                        )
                    }
                }

                if !viewModel.recentlyAdded.isEmpty {
                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            MediaHubSection(title: hub.title) {
                                MediaCarousel(
                                    layout: .portrait,
                                    items: hub.items,
                                    showsLabels: true,
                                    onSelectMedia: onSelectMedia
                                )
                            }
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("home.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("tabs.home")
        .task {
            await viewModel.load()
        }
    }
}
