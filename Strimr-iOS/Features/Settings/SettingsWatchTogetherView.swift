import SwiftUI

struct SettingsWatchTogetherView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchTogetherViewModel.self) private var watchTogetherViewModel

    @State private var customURL: String = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connection")
                        .font(.headline)

                    if let resolved = watchTogetherViewModel.resolvedServerURL {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(resolved.absoluteString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                            Text("Not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("The server is discovered automatically. It checks: custom URL, build config, Plex server host, then local network (mDNS).")
            }

            Section {
                TextField("wss://example.com:8080", text: $customURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if !customURL.isEmpty {
                    Button("Clear", role: .destructive) {
                        customURL = ""
                        settingsManager.setWatchTogetherServerURL(nil)
                    }
                }
            } header: {
                Text("Custom Server URL")
            } footer: {
                Text("Only set this if your Watch Together server is not on the same machine as your Plex server. Leave blank for automatic discovery.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Watch Together Server")
        .onAppear {
            customURL = settingsManager.watchTogether.customServerURL ?? ""
        }
        .onChange(of: customURL) { _, newValue in
            settingsManager.setWatchTogetherServerURL(newValue)
        }
    }
}
