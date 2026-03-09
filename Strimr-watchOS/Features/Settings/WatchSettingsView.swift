import SwiftUI

struct WatchSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(WatchDownloadManager.self) private var downloadManager

    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        List {
            Section {
                Toggle("Offline Mode", isOn: offlineModeBinding)
            } footer: {
                Text("Only show downloaded content. No network requests.")
            }

            Section {
                Picker("Stream Quality", selection: streamQualityBinding) {
                    ForEach(StreamQuality.watchCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }

                Toggle("Zoom Video", isOn: zoomVideoBinding)
            } header: {
                Text("Streaming")
            } footer: {
                Text("Zoom crops black bars by filling the screen.")
            }

            Section {
                Picker("Audio Downloads", selection: audioDownloadQualityBinding) {
                    ForEach(AudioDownloadQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
            } header: {
                Text("Downloads")
            } footer: {
                Text("Transcodes lossless audio (FLAC, ALAC) to MP3 256kbps. Lossy files download as-is.")
            }

            Section("Storage") {
                let summary = downloadManager.storageSummary
                let downloadsText = ByteCountFormatter.string(
                    fromByteCount: summary.downloadsBytes,
                    countStyle: .file
                )
                let availableText = ByteCountFormatter.string(
                    fromByteCount: summary.availableBytes,
                    countStyle: .file
                )

                LabeledContent("Downloads", value: downloadsText)
                LabeledContent("Available", value: availableText)
                LabeledContent("Items", value: "\(completedCount)")
            }

            Section {
                NavigationLink {
                    WatchServerSelectionView()
                } label: {
                    Label("Switch Server", systemImage: "server.rack")
                }

                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Label("Log Out", systemImage: "arrow.backward.circle")
                }
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Log Out", isPresented: $isShowingLogoutConfirmation) {
            Button("Log Out", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to log out?")
        }
    }

    private var zoomVideoBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.playback.zoomVideo },
            set: { settingsManager.setZoomVideo($0) }
        )
    }

    private var streamQualityBinding: Binding<StreamQuality> {
        Binding(
            get: { settingsManager.playback.streamQuality },
            set: { settingsManager.setStreamQuality($0) }
        )
    }

    private var audioDownloadQualityBinding: Binding<AudioDownloadQuality> {
        Binding(
            get: { settingsManager.downloads.audioQuality },
            set: { settingsManager.setAudioDownloadQuality($0) }
        )
    }

    private var offlineModeBinding: Binding<Bool> {
        Binding(
            get: { settingsManager.settings.interface.offlineMode },
            set: { settingsManager.setOfflineMode($0) }
        )
    }

    private var completedCount: Int {
        downloadManager.items.filter { $0.status == .completed }.count
    }
}
