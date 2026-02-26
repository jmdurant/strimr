import SwiftUI

struct WatchLibrariesView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore

    @State private var viewModel: LibraryViewModel?

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading && viewModel.libraries.isEmpty {
                    ProgressView()
                } else if viewModel.libraries.isEmpty {
                    ContentUnavailableView(
                        "No Libraries",
                        systemImage: "books.vertical",
                        description: Text(viewModel.errorMessage ?? "No libraries found")
                    )
                } else {
                    List(viewModel.libraries) { library in
                        NavigationLink(value: library) {
                            Label(library.title, systemImage: library.iconName)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Libraries")
        .navigationDestination(for: Library.self) { library in
            WatchLibraryDetailView(library: library)
        }
        .task {
            let vm = LibraryViewModel(context: plexApiContext, libraryStore: libraryStore)
            viewModel = vm
            await vm.load()
        }
    }
}
