import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaItem) -> Void

    private let gridColumns = [
        GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(viewModel.items) { media in
                    PortraitMediaCard(media: media) {
                        onSelectMedia(media)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .task {
                        if media == viewModel.items.last {
                            await viewModel.loadMore()
                        }
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView("Loading library")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(errorMessage, systemImage: "exclamationmark.triangle.fill", description: Text("Try again later."))
                    .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView("No items", systemImage: "square.grid.2x2.fill", description: Text("Nothing to browse yet."))
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

#Preview {
    let api = PlexAPIManager()
    let viewModel = LibraryBrowseViewModel(
        library: Library(id: "1", title: "Movies", type: .movie, sectionId: 1),
        plexApiManager: api
    )
    viewModel.items = []

    return LibraryBrowseView(
        viewModel: viewModel,
        onSelectMedia: { _ in }
    )
    .environment(api)
}
