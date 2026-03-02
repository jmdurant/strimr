import SwiftUI

@MainActor
struct WatchSyncView: View {
    @Environment(WatchSyncManager.self) private var syncManager
    @Environment(PlexAPIContext.self) private var context
    @Environment(LibraryStore.self) private var libraryStore

    @State private var showBrowse = false

    var body: some View {
        List {
            watchStatusSection
            if !syncManager.syncItems.isEmpty {
                syncItemsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Watch Sync")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showBrowse = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!syncManager.isWatchPaired)
            }
        }
        .sheet(isPresented: $showBrowse) {
            NavigationStack {
                WatchSyncBrowseView()
            }
        }
    }

    @ViewBuilder
    private var watchStatusSection: some View {
        Section {
            HStack {
                Image(systemName: syncManager.isWatchPaired ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .foregroundStyle(syncManager.isWatchPaired ? .green : .secondary)
                Text(syncManager.isWatchPaired ? "Apple Watch Connected" : "Apple Watch Not Paired")
            }
        }
    }

    @ViewBuilder
    private var syncItemsSection: some View {
        Section {
            ForEach(syncManager.syncItems) { item in
                WatchSyncItemRow(item: item)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            syncManager.cancelSync(item)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
            }
        } header: {
            HStack {
                Text("Sync Queue")
                Spacer()
                if syncManager.syncItems.contains(where: { $0.status == .completed }) {
                    Button("Clear Done") {
                        syncManager.clearCompleted()
                    }
                    .font(.caption)
                    .textCase(nil)
                }
            }
        }
    }
}

private struct WatchSyncItemRow: View {
    let item: WatchSyncItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.body)
                .lineLimit(1)

            if let artist = item.artistName {
                Text(artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                statusIcon
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                if item.isActive && item.status != .transferring {
                    Spacer()
                    ProgressView(value: item.progress)
                        .frame(width: 80)
                }
            }

            if let error = item.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.blue)
        case .transferring:
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .queued: "Queued"
        case .downloading: "Downloading..."
        case .transferring: "Transferring to Watch..."
        case .completed: "Synced"
        case .failed: "Failed"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .queued: .secondary
        case .downloading: .blue
        case .transferring: .orange
        case .completed: .green
        case .failed: .red
        }
    }
}
