import SwiftUI

struct ServerSelectionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            header
            content
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .help("Sign Out")
            }
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("serverSelection.title")
                .font(.largeTitle.bold())
            Text("serverSelection.subtitle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.servers.isEmpty {
            ProgressView("serverSelection.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if viewModel.servers.isEmpty {
            VStack(spacing: 12) {
                Text("serverSelection.empty.title")
                    .font(.headline)
                Text("serverSelection.empty.description")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    HStack {
                        if viewModel.isLoading { ProgressView().controlSize(.small) }
                        Text("serverSelection.retry")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(viewModel.isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.servers, id: \.clientIdentifier) { server in
                        serverRow(server)
                    }
                }
                .frame(maxWidth: 500)
                .padding(.vertical, 8)
            }
        }
    }

    private func serverRow(_ server: PlexCloudResource) -> some View {
        Button {
            Task { await viewModel.select(server: server) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    connectionSummary(for: server)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.selectingServerID == server.clientIdentifier {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(
                viewModel.isSelecting && viewModel.selectingServerID != server.clientIdentifier
                    ? 0.6
                    : 1
            )
            .padding()
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSelecting)
    }

    private func connectionSummary(for server: PlexCloudResource) -> some View {
        guard let connection = server.connections?.first else {
            return Text("serverSelection.connection.unavailable")
        }
        if connection.isLocal {
            return Text("serverSelection.connection.localFormat \(connection.address)")
        }
        if connection.isRelay {
            return Text("serverSelection.connection.relay")
        }
        return Text(connection.address)
    }
}
