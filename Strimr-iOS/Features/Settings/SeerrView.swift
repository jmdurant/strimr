import SwiftUI

@MainActor
struct SeerrView: View {
    @Bindable var viewModel: SeerrViewModel
    @State private var isEditingServer = false

    var body: some View {
        List {
            if viewModel.user == nil {
                if let baseURL = viewModel.baseURLString, !isEditingServer {
                    Section("integrations.seerr.server.title") {
                        HStack(spacing: 8) {
                            Text(baseURL)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)

                            Button {
                                viewModel.baseURLInput = baseURL
                                isEditingServer = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .tint(.white)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("common.actions.edit")
                        }
                    }
                } else {
                    Section("integrations.seerr.server.title") {
                        TextField(
                            "integrations.seerr.server.url.title",
                            text: $viewModel.baseURLInput,
                            prompt: Text("integrations.seerr.server.url.placeholder"),
                        )
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            Task {
                                await viewModel.validateServer()
                                if viewModel.baseURLString != nil {
                                    isEditingServer = false
                                }
                            }
                        } label: {
                            Label("integrations.seerr.server.save", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .tint(.secondary)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || viewModel.isValidating)
                    }
                }
            } else if let baseURL = viewModel.baseURLString {
                Section("integrations.seerr.server.title") {
                    LabeledContent("integrations.seerr.server.url.title") {
                        HStack(spacing: 8) {
                            Text(baseURL)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }

            if viewModel.user == nil, viewModel.baseURLString != nil {
                Section("integrations.seerr.login.title") {
                    VStack(alignment: .leading, spacing: 12) {
                        
                        VStack(alignment: .leading) {
                            Text("integrations.seerr.login.plex.title")
                                .font(.headline)
                            
                            Button {
                                Task {
                                    await viewModel.signInWithPlex()
                                }
                            } label: {
                                Label("integrations.seerr.login.plex", systemImage: "person.fill.checkmark")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .tint(.secondary)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(!viewModel.isPlexAuthAvailable || viewModel.isAuthenticating)
                            
                            if !viewModel.isPlexAuthAvailable {
                                Text("integrations.seerr.login.plex.unavailable")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading) {
                            Text("integrations.seerr.login.local.title")
                                .font(.headline)
                            
                            TextField("integrations.seerr.login.email", text: $viewModel.email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            
                            SecureField("integrations.seerr.login.password", text: $viewModel.password)
                            
                            Button {
                                Task {
                                    await viewModel.signInWithLocal()
                                }
                            } label: {
                                Label("integrations.seerr.login.local", systemImage: "arrow.right.circle.fill")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .tint(.secondary)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(viewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty || viewModel.password.isEmpty || viewModel.isAuthenticating)
                        }
                    }
                }
            }

            if let user = viewModel.user {
                Section("integrations.seerr.account.title") {
                    LabeledContent("integrations.seerr.account.userId") {
                        Text("\(user.id)")
                    }
                }

                Section {
                    Button("integrations.seerr.actions.signOut", role: .destructive) {
                        viewModel.signOut()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("integrations.seerr.title")
        .alert("integrations.seerr.error.title", isPresented: $viewModel.isShowingError) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}
