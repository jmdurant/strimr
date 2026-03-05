import PhotosUI
import SwiftUI

@MainActor
struct SettingsInterfaceView: View {
    let settingsManager: SettingsManager
    let libraryStore: LibraryStore
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var bannerPreview: UIImage?
    @State private var bannerText: String = ""

    var body: some View {
        List {
            Section("Appearance") {
                accentColorPicker
                appearanceModePicker
            }

            Section("Custom Home Banner") {
                customBannerPicker
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
        .onAppear {
            if let data = settingsManager.loadCustomBannerData() {
                bannerPreview = UIImage(data: data)
            }
            bannerText = settingsManager.interface.customBannerText
        }
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

    @ViewBuilder
    private var customBannerPicker: some View {
        Toggle(
            "Show Banner",
            isOn: Binding(
                get: { settingsManager.interface.customBannerEnabled },
                set: { newValue in
                    settingsManager.setCustomBanner(enabled: newValue)
                },
            )
        )

        if settingsManager.interface.customBannerEnabled {
            if let bannerPreview {
                Image(uiImage: bannerPreview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            PhotosPicker(
                selection: $selectedPhoto,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    bannerPreview != nil ? "Change Photo" : "Choose Photo",
                    systemImage: "photo.on.rectangle"
                )
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }

            if bannerPreview != nil {
                Button("Remove Photo", role: .destructive) {
                    settingsManager.setCustomBanner(imageData: nil)
                    bannerPreview = nil
                    selectedPhoto = nil
                }
            }

            HStack {
                Text("Banner Text")
                Spacer()
                TextField("Welcome to Plex!", text: $bannerText)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .onSubmit {
                        settingsManager.setCustomBannerText(bannerText)
                    }
                    .onChange(of: bannerText) { _, newValue in
                        settingsManager.setCustomBannerText(newValue)
                    }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let original = UIImage(data: data)
        else { return }

        // Resize to banner proportions and compress
        let targetWidth: CGFloat = 800
        let aspectRatio = original.size.height / original.size.width
        let targetSize = CGSize(width: targetWidth, height: targetWidth * aspectRatio)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else { return }
        settingsManager.setCustomBanner(imageData: jpegData)
        bannerPreview = resized
    }
}
