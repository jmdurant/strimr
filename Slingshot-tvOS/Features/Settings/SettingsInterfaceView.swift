import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore

    var body: some View {
        List {
            Section("Appearance") {
                accentColorPicker
                appearanceModePicker
            }

            Section {
                Toggle(
                    "settings.interface.displayCollections",
                    isOn: Binding(
                        get: { settingsManager.interface.displayCollections },
                        set: { settingsManager.setDisplayCollections($0) },
                    ),
                )
                Toggle(
                    "settings.interface.displayPlaylists",
                    isOn: Binding(
                        get: { settingsManager.interface.displayPlaylists },
                        set: { settingsManager.setDisplayPlaylists($0) },
                    ),
                )
            }

            DisplayedLibrariesSectionView(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            )

            NavigationLibrariesSectionView(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            )
        }
        .navigationTitle("settings.interface.title")
    }

    private var accentColorPicker: some View {
        HStack {
            Text("Accent Color")
            Spacer()
            HStack(spacing: 12) {
                ForEach(AccentColorOption.allCases, id: \.self) { option in
                    Button {
                        settingsManager.setAccentColor(option)
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .strokeBorder(.white, lineWidth: settingsManager.interface.accentColor == option ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var appearanceModePicker: some View {
        Picker("Appearance", selection: Binding(
            get: { settingsManager.interface.appearance },
            set: { settingsManager.setAppearance($0) }
        )) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
    }
}
