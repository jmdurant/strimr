import SwiftUI

struct WatchHomeView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    @State var viewModel: HomeViewModel

    var body: some View {
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
                            ForEach(continueWatching.items) { item in
                                WatchMediaRow(item: item)
                            }
                        }
                    }

                    ForEach(viewModel.recentlyAdded) { hub in
                        if hub.hasItems {
                            Section(hub.title) {
                                ForEach(hub.items) { item in
                                    WatchMediaRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationDestination(for: PlayableMediaItem.self) { media in
            WatchMediaDetailView(media: media)
        }
        .navigationTitle("Home")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.reload()
        }
    }
}
