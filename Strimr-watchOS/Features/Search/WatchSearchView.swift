import SwiftUI

struct WatchSearchView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext

    @State private var viewModel: SearchViewModel?

    var body: some View {
        Group {
            if let viewModel {
                @Bindable var vm = viewModel
                List {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if viewModel.hasQuery && viewModel.filteredItems.isEmpty {
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
        .navigationTitle("Search")
        .task {
            viewModel = SearchViewModel(context: plexApiContext)
        }
    }
}
