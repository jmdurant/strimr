import SwiftUI

struct WatchProfileSelectionView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SessionManager.self) private var sessionManager

    @State private var viewModel: ProfileSwitcherViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List(viewModel.users, id: \.uuid) { user in
                        Button {
                            Task {
                                await viewModel.switchToUser(user, pin: nil)
                            }
                        } label: {
                            HStack {
                                Text(user.friendlyName ?? user.title ?? "User")
                                Spacer()
                                if user.uuid == viewModel.activeUserUUID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Profile")
            .task {
                let vm = ProfileSwitcherViewModel(
                    context: plexApiContext,
                    sessionManager: sessionManager
                )
                viewModel = vm
                await vm.loadUsers()
            }
        }
    }
}
