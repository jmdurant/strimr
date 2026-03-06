import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(WatchTogetherViewModel.self) private var watchTogetherViewModel

    var body: some View {
        TabView {
            playbackTab
                .tabItem {
                    Label("Playback", systemImage: "play.circle")
                }

            interfaceTab
                .tabItem {
                    Label("Interface", systemImage: "paintbrush")
                }

            watchTogetherTab
                .tabItem {
                    Label("Watch Together", systemImage: "person.2.fill")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }

    private var playbackTab: some View {
        let viewModel = SettingsViewModel(settingsManager: settingsManager)

        return Form {
            Toggle("settings.playback.autoPlayNext", isOn: viewModel.autoPlayNextBinding)

            Picker("settings.playback.rewind", selection: viewModel.rewindBinding) {
                ForEach(viewModel.seekOptions, id: \.self) { seconds in
                    Text("settings.playback.seconds \(seconds)").tag(seconds)
                }
            }

            Picker("settings.playback.fastForward", selection: viewModel.fastForwardBinding) {
                ForEach(viewModel.seekOptions, id: \.self) { seconds in
                    Text("settings.playback.seconds \(seconds)").tag(seconds)
                }
            }

            Picker("settings.playback.player", selection: viewModel.playerBinding) {
                ForEach(viewModel.playerOptions) { player in
                    Text(LocalizedStringKey(player.localizationKey)).tag(player)
                }
            }

            Picker("settings.playback.subtitleScale", selection: viewModel.subtitleScaleBinding) {
                ForEach(viewModel.subtitleScaleOptions, id: \.self) { scale in
                    Text("settings.playback.scale \(scale)").tag(scale)
                }
            }

            Picker("Stream Quality", selection: viewModel.streamQualityBinding) {
                ForEach(StreamQuality.allCases) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }
        }
        .padding()
    }

    private var interfaceTab: some View {
        Form {
            Picker("Accent Color", selection: Binding(
                get: { settingsManager.interface.accentColor },
                set: { settingsManager.setAccentColor($0) }
            )) {
                ForEach(AccentColorOption.allCases, id: \.self) { option in
                    HStack {
                        Circle().fill(option.color).frame(width: 12, height: 12)
                        Text(option.displayName)
                    }
                    .tag(option)
                }
            }

            Picker("Appearance", selection: Binding(
                get: { settingsManager.interface.appearance },
                set: { settingsManager.setAppearance($0) }
            )) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Toggle(
                "settings.interface.displayCollections",
                isOn: Binding(
                    get: { settingsManager.interface.displayCollections },
                    set: { settingsManager.setDisplayCollections($0) }
                )
            )

            Toggle(
                "settings.interface.displayPlaylists",
                isOn: Binding(
                    get: { settingsManager.interface.displayPlaylists },
                    set: { settingsManager.setDisplayPlaylists($0) }
                )
            )
        }
        .padding()
    }

    private var watchTogetherTab: some View {
        Form {
            if let resolved = watchTogetherViewModel.resolvedServerURL {
                LabeledContent("Connection") {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(resolved.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                LabeledContent("Connection") {
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                }
            }

            Text("The server is discovered automatically. It checks: custom URL, build config, Plex server host, then local network (mDNS).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var aboutTab: some View {
        AboutView()
    }
}
