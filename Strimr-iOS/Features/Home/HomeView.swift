import SwiftUI

@MainActor
struct HomeView: View {
    @State var viewModel: HomeViewModel
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore
    @State private var bannerData: Data?
    @State private var bannerArtworkURLs: [String: URL] = [:]
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onSelectLibrary: (Library) -> Void
    let onSelectLiveTV: () -> Void

    init(
        viewModel: HomeViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onSelectLibrary: @escaping (Library) -> Void = { _ in },
        onSelectLiveTV: @escaping () -> Void = {},
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onSelectLibrary = onSelectLibrary
        self.onSelectLiveTV = onSelectLiveTV
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if settingsManager.interface.customBannerEnabled {
                    CustomBannerCard(
                        bannerText: settingsManager.interface.customBannerText,
                        customImageData: bannerData,
                        libraries: libraryStore.libraries,
                        artworkURLForLibrary: { library in
                            bannerArtworkURLs[library.id]
                        },
                        hasLiveTV: libraryStore.hasLiveTV,
                        onSelectLibrary: onSelectLibrary,
                        onSelectLiveTV: onSelectLiveTV
                    )
                }

                if let hub = viewModel.continueWatching, hub.hasItems {
                    MediaHubSection(title: hub.title) {
                        MediaCarousel(
                            layout: .landscape,
                            items: hub.items,
                            showsLabels: true,
                            onSelectMedia: onSelectMedia,
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
                                    onSelectMedia: onSelectMedia,
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
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .navigationTitle("tabs.home")
        .navigationBarTitleDisplayMode(.inline)
        .userMenuToolbar()
        .task {
            await viewModel.load()
        }
        .task {
            await loadBannerArtwork()
        }
        .refreshable {
            await viewModel.reload()
        }
        .onAppear {
            bannerData = settingsManager.loadCustomBannerData()
        }
        .onChange(of: settingsManager.interface.customBannerVersion) { _, _ in
            bannerData = settingsManager.loadCustomBannerData()
        }
    }

    private func loadBannerArtwork() async {
        guard let imageRepo = try? ImageRepository(context: plexApiContext),
              let sectionRepo = try? SectionRepository(context: plexApiContext)
        else { return }

        for library in libraryStore.libraries {
            guard bannerArtworkURLs[library.id] == nil,
                  let sectionId = library.sectionId
            else { continue }

            // Use the right content type for each library
            let contentType: String? = switch library.type {
            case .artist: "9"   // albums (have artwork)
            case .photo: "13"   // photo albums
            default: nil        // movies/shows work without type filter
            }

            do {
                let container = try await sectionRepo.getSectionsItems(
                    sectionId: sectionId,
                    params: SectionRepository.SectionItemsParams(sort: "random", limit: 1, type: contentType),
                    pagination: PlexPagination(start: 0, size: 1),
                )
                if let item = container.mediaContainer.metadata?.first,
                   let path = item.art ?? item.thumb,
                   let url = imageRepo.transcodeImageURL(path: path, width: 800, height: 450)
                {
                    bannerArtworkURLs[library.id] = url
                }
            } catch {}
        }
    }
}
