import SwiftUI

struct WatchSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(WatchDownloadManager.self) private var downloadManager

    var body: some View {
        List {
            Section {
                Toggle("Offline Mode", isOn: offlineModeBinding)
            } footer: {
                Text("Only show downloaded content. No network requests.")
            }

            Section {
                Picker("Stream Quality", selection: streamQualityBinding) {
                    ForEach(StreamQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }

                Toggle("Zoom Video", isOn: zoomVideoBinding)
            } header: {
                Text("Streaming")
            } footer: {
                Text("Zoom crops black bars by filling the screen.")
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
        }
        .navigationTitle("Settings")
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
