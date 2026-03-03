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
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("settings.interface.title")
    }

    private var accentColorPicker: some View {
        HStack {
            Text("Accent Color")
            Spacer()
            HStack(spacing: 8) {
                ForEach(AccentColorOption.allCases, id: \.self) { option in
                    Circle()
                        .fill(option.color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: settingsManager.interface.accentColor == option ? 2 : 0)
                        )
                        .onTapGesture {
                            settingsManager.setAccentColor(option)
                        }
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
