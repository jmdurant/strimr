import SwiftUI

@MainActor
struct SearchView: View {
    @State var viewModel: SearchViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: SearchViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        VStack(spacing: 0) {
            filterPills()
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                resultsContent()
                    .padding(20)
            }
        }
        .navigationTitle("tabs.search")
        .searchable(
            text: $bindableViewModel.query,
            placement: .toolbar,
            prompt: "search.prompt"
        )
        .onChange(of: bindableViewModel.query) { _, _ in
            viewModel.queryDidChange()
        }
        .onSubmit(of: .search) {
            viewModel.submitSearch()
        }
    }

    @ViewBuilder
    private func resultsContent() -> some View {
        if !viewModel.hasQuery {
            ContentUnavailableView(
                "search.empty.title",
                systemImage: "magnifyingglass",
                description: Text("search.empty.description")
            )
            .frame(maxWidth: .infinity)
        } else if viewModel.isLoading {
            ProgressView("search.loading")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.filteredItems.isEmpty {
            ContentUnavailableView(
                "search.noResults.title",
                systemImage: "film.stack.fill",
                description: Text("search.noResults.description")
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], spacing: 16) {
                ForEach(viewModel.filteredItems) { media in
                    PortraitMediaCard(media: media, showsLabels: true) {
                        onSelectMedia(media)
                    }
                }
            }
        }
    }

    private func filterPills() -> some View {
        HStack(spacing: 8) {
            ForEach(SearchFilter.allCases) { filter in
                let isSelected = viewModel.activeFilters.contains(filter)
                Button {
                    viewModel.toggleFilter(filter)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filter.systemImageName)
                            .font(.subheadline)
                        Text(filter.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.25), lineWidth: 1)
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
