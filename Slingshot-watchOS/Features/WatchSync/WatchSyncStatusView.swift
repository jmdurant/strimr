import SwiftUI

struct WatchSyncStatusView: View {
    @Environment(WatchDownloadManager.self) private var downloadManager

    private var syncedTrackCount: Int {
        downloadManager.items.filter { $0.status == .completed && $0.metadata.type == .track }.count
    }

    var body: some View {
        if syncedTrackCount > 0 {
            Section("Synced from iPhone") {
                LabeledContent("Tracks", value: "\(syncedTrackCount)")
            }
        }
    }
}
