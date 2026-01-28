import SwiftUI

@MainActor
struct SeerrDiscoverView: View {
    @State var viewModel: SeerrDiscoverViewModel
    let onSelectMedia: (SeerrMedia) -> Void

    init(
        viewModel: SeerrDiscoverViewModel,
        onSelectMedia: @escaping (SeerrMedia) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isSearchActive {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.searchResults, id: \.id) { media in
                            SeerrSearchCard(media: media) {
                                onSelectMedia(media)
                            }
                        }
                    }
                } else {
                    if !viewModel.trending.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.trending") {
                            SeerrMediaCarousel(
                                items: viewModel.trending,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }

                    if !viewModel.popularMovies.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.popularMovies") {
                            SeerrMediaCarousel(
                                items: viewModel.popularMovies,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }

                    if !viewModel.popularTV.isEmpty {
                        SeerrMediaSection(title: "integrations.seerr.discover.popularTV") {
                            SeerrMediaCarousel(
                                items: viewModel.popularTV,
                                showsLabels: true,
                                onSelectMedia: onSelectMedia,
                            )
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("integrations.seerr.discover.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading, !viewModel.isSearchActive {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                } else if viewModel.isSearchActive, !viewModel.isSearching, viewModel.searchResults.isEmpty {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.discover")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
        .task(id: viewModel.searchQuery) {
            await viewModel.search()
        }
        .refreshable {
            await viewModel.reload()
        }
        .searchable(
            text: $viewModel.searchQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("integrations.seerr.search.placeholder"),
        )
    }
}
