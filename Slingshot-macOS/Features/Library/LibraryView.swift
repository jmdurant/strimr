import SwiftUI

struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onSelectLibrary: (Library) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 16)
    ]

    init(
        viewModel: LibraryViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onSelectLibrary: @escaping (Library) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onSelectLibrary = onSelectLibrary
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                if libraryStore.hasLiveTV {
                    liveTVCard
                }

                ForEach(visibleLibraries) { library in
                    libraryCard(for: library)
                }

                if !hiddenLibraries.isEmpty {
                    Section {
                        ForEach(hiddenLibraries) { library in
                            libraryCard(for: library)
                                .opacity(0.6)
                        }
                    }
                }
            }
            .padding(24)
        }
        .overlay {
            if viewModel.isLoading, viewModel.libraries.isEmpty {
                ProgressView("Loading libraries...")
            } else if let errorMessage = viewModel.errorMessage, viewModel.libraries.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("Unable to load libraries from the server.")
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.libraries.isEmpty {
                ContentUnavailableView(
                    "No Libraries",
                    systemImage: "rectangle.stack.fill",
                    description: Text("No libraries found on this server.")
                )
            }
        }
        .navigationTitle("Libraries")
        .task {
            await viewModel.load()
        }
    }

    private var hiddenLibraryIds: Set<String> {
        Set(settingsManager.interface.hiddenLibraryIds)
    }

    private var visibleLibraries: [Library] {
        viewModel.libraries.filter { !hiddenLibraryIds.contains($0.id) }
    }

    private var hiddenLibraries: [Library] {
        viewModel.libraries.filter { hiddenLibraryIds.contains($0.id) }
    }

    private var liveTVCard: some View {
        Button {
            // Navigation handled by parent
        } label: {
            ZStack(alignment: .bottomLeading) {
                Color.indigo.opacity(0.3)
                    .frame(minHeight: 120)

                LinearGradient(
                    colors: [.black.opacity(0.6), .black.opacity(0.2), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )

                HStack(spacing: 10) {
                    Image(systemName: "tv")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live TV")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Watch live channels")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func libraryCard(for library: Library) -> some View {
        Button {
            onSelectLibrary(library)
        } label: {
            ZStack(alignment: .bottomLeading) {
                if let artwork = viewModel.artworkURL(for: library) {
                    AsyncImage(url: artwork) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        default:
                            Color.gray.opacity(0.1)
                        }
                    }
                    .frame(minHeight: 120)
                    .clipped()
                } else {
                    Color.gray.opacity(0.08)
                        .frame(minHeight: 120)
                }

                LinearGradient(
                    colors: [.black.opacity(0.6), .black.opacity(0.2), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )

                HStack(spacing: 10) {
                    Image(systemName: library.iconName)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.title)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(library.type.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .task {
            await viewModel.ensureArtwork(for: library)
        }
    }
}
