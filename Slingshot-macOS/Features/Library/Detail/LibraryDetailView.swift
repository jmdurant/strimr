import SwiftUI

struct LibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var viewModel: LibraryRecommendedViewModel?

    init(
        library: Library,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in }
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            if let viewModel {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.hubs) { hub in
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

                    if viewModel.isLoading, !viewModel.hasContent {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if !viewModel.hasContent, !viewModel.isLoading {
                        ContentUnavailableView(
                            "Nothing to show",
                            systemImage: "rectangle.stack.fill",
                            description: Text("This library is empty.")
                        )
                    }
                }
                .padding(20)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
            }
        }
        .navigationTitle(library.title)
        .task {
            if viewModel == nil {
                let vm = LibraryRecommendedViewModel(
                    library: library,
                    context: plexApiContext
                )
                viewModel = vm
                await vm.load()
            }
        }
    }
}
