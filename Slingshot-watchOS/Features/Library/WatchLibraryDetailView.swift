import SwiftUI

struct WatchLibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    let library: Library

    @State private var viewModel: LibraryRecommendedViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && !viewModel.hasContent {
                    ProgressView()
                } else if !viewModel.hasContent {
                    ContentUnavailableView(
                        "Empty",
                        systemImage: "tray",
                        description: Text(viewModel.errorMessage ?? "No content found")
                    )
                } else {
                    List {
                        ForEach(viewModel.hubs) { hub in
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
            } else {
                ProgressView()
            }
        }
        .navigationDestination(for: PlayableMediaItem.self) { media in
            WatchMediaDetailView(media: media)
        }
        .navigationDestination(for: PlaylistMediaItem.self) { playlist in
            WatchPlaylistDetailView(playlist: playlist)
        }
        .navigationTitle(library.title)
        .task {
            let vm = LibraryRecommendedViewModel(library: library, context: plexApiContext)
            viewModel = vm
            await vm.load()
        }
    }
}
