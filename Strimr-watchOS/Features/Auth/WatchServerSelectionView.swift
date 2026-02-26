import SwiftUI

struct WatchServerSelectionView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SessionManager.self) private var sessionManager

    @State private var viewModel: ServerSelectionViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if viewModel.servers.isEmpty {
                        ContentUnavailableView(
                            "No Servers",
                            systemImage: "server.rack",
                            description: Text("No Plex servers found")
                        )
                    } else {
                        List(viewModel.servers, id: \.clientIdentifier) { server in
                            Button {
                                Task {
                                    await sessionManager.selectServer(server)
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                        .font(.headline)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Server")
            .task {
                let vm = ServerSelectionViewModel(
                    sessionManager: sessionManager,
                    context: plexApiContext
                )
                viewModel = vm
                await vm.load()
            }
        }
    }
}
