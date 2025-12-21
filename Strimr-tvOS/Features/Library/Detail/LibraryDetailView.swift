import SwiftUI

struct LibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    let library: Library
    let onSelectMedia: (MediaItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended

    init(
        library: Library,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        self.library = library
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            if selectedTab == .recommended {
                ZStack(alignment: .top) {
                    LibraryTVRecommendedView(
                        viewModel: LibraryRecommendedViewModel(
                            library: library,
                            context: plexApiContext
                        ),
                        onSelectMedia: onSelectMedia
                    )
                    pickerView
                }
            } else {
                VStack(spacing: 0) {
                    pickerView
                    LibraryBrowseView(onSelectMedia: onSelectMedia)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private var pickerView: some View {
        Picker("library.detail.tabPicker", selection: $selectedTab) {
            ForEach(LibraryDetailTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 48)
    }
}

enum LibraryDetailTab: String, CaseIterable, Identifiable {
    case recommended
    case browse

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .recommended:
            return "library.detail.tab.recommended"
        case .browse:
            return "library.detail.tab.browse"
        }
    }
}
