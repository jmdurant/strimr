import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchSyncManager: NSObject {
    private(set) var syncItems: [WatchSyncItem] = []

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private weak var downloadManager: DownloadManager?
    @ObservationIgnored private let syncDirectory: URL
    @ObservationIgnored private let indexFileURL: URL
    @ObservationIgnored private var isProcessing = false
    @ObservationIgnored private var activeTransfers: [String: WCSessionFileTransfer] = [:]

    init(context: PlexAPIContext, downloadManager: DownloadManager? = nil) {
        self.context = context
        self.downloadManager = downloadManager
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        syncDirectory = appSupport.appendingPathComponent("WatchSync", isDirectory: true)
        indexFileURL = syncDirectory.appendingPathComponent("index.json", isDirectory: false)
        super.init()
        try? FileManager.default.createDirectory(at: syncDirectory, withIntermediateDirectories: true)
        loadPersistedState()
    }

    // MARK: - Public API

    var isWatchPaired: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isPaired
    }

    func syncAlbum(ratingKey: String) async {
        do {
            let metadataRepo = try MetadataRepository(context: context)
            let response = try await metadataRepo.getMetadataChildren(ratingKey: ratingKey)
            guard let tracks = response.mediaContainer.metadata else { return }

            for plexItem in tracks where plexItem.type == .track {
                queueTrack(plexItem: plexItem)
            }
            persistState()
            await processQueue()
        } catch {
            debugPrint("[WatchSync] syncAlbum failed: \(error)")
        }
    }

    func syncPlaylist(ratingKey: String) async {
        do {
            let playlistRepo = try PlaylistRepository(context: context)
            let response = try await playlistRepo.getPlaylistItems(ratingKey: ratingKey)
            guard let items = response.mediaContainer.metadata else { return }

            for plexItem in items where plexItem.type == .track {
                queueTrack(plexItem: plexItem)
            }
            persistState()
            await processQueue()
        } catch {
            debugPrint("[WatchSync] syncPlaylist failed: \(error)")
        }
    }

    func syncTrack(ratingKey: String) async {
        do {
            let metadataRepo = try MetadataRepository(context: context)
            let response = try await metadataRepo.getMetadata(
                ratingKey: ratingKey,
                params: .init(checkFiles: true)
            )
            guard let plexItem = response.mediaContainer.metadata?.first,
                  plexItem.type == .track else { return }

            queueTrack(plexItem: plexItem)
            persistState()
            await processQueue()
        } catch {
            debugPrint("[WatchSync] syncTrack failed: \(error)")
        }
    }

    func cancelSync(_ item: WatchSyncItem) {
        if let transfer = activeTransfers[item.id] {
            transfer.cancel()
            activeTransfers.removeValue(forKey: item.id)
        }

        // Clean up temp file
        let tempDir = syncDirectory.appendingPathComponent(item.id, isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)

        syncItems.removeAll { $0.id == item.id }
        persistState()
    }

    func clearCompleted() {
        let completedIds = syncItems.filter { $0.status == .completed }.map(\.id)
        for id in completedIds {
            let tempDir = syncDirectory.appendingPathComponent(id, isDirectory: true)
            try? FileManager.default.removeItem(at: tempDir)
        }
        syncItems.removeAll { $0.status == .completed }
        persistState()
    }

    func retryFailed() async {
        for i in syncItems.indices where syncItems[i].status == .failed {
            syncItems[i].status = .queued
            syncItems[i].progress = 0
            syncItems[i].errorMessage = nil
        }
        persistState()
        await processQueue()
    }

    // MARK: - Transfer Callbacks

    func handleTransferComplete(fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let itemId = activeTransfers.first(where: { $0.value === fileTransfer })?.key else { return }
        activeTransfers.removeValue(forKey: itemId)

        guard let idx = syncItems.firstIndex(where: { $0.id == itemId }) else { return }

        if let error {
            syncItems[idx].status = .failed
            syncItems[idx].errorMessage = error.localizedDescription
        } else {
            syncItems[idx].status = .completed
            syncItems[idx].progress = 1
        }

        // Clean up temp file
        let tempDir = syncDirectory.appendingPathComponent(itemId, isDirectory: true)
        try? FileManager.default.removeItem(at: tempDir)

        persistState()

        Task {
            await processQueue()
        }
    }

    // MARK: - Private

    private func queueTrack(plexItem: PlexItem) {
        guard !syncItems.contains(where: { $0.ratingKey == plexItem.ratingKey && $0.status != .failed }) else {
            return
        }

        // Remove previous failed attempts for the same track
        syncItems.removeAll { $0.ratingKey == plexItem.ratingKey && $0.status == .failed }

        let item = WatchSyncItem(
            id: UUID().uuidString,
            ratingKey: plexItem.ratingKey,
            status: .queued,
            progress: 0,
            title: plexItem.title,
            artistName: plexItem.grandparentTitle,
            albumName: plexItem.parentTitle,
            createdAt: Date()
        )
        syncItems.append(item)
    }

    private func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let idx = syncItems.firstIndex(where: { $0.status == .queued }) {
            let item = syncItems[idx]
            await processItem(item)
        }
    }

    private func processItem(_ item: WatchSyncItem) async {
        guard let idx = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
        syncItems[idx].status = .downloading
        persistState()

        do {
            // 1. Fetch full metadata with file info
            let metadataRepo = try MetadataRepository(context: context)
            let response = try await metadataRepo.getMetadata(
                ratingKey: item.ratingKey,
                params: .init(checkFiles: true)
            )
            guard let plexItem = response.mediaContainer.metadata?.first else {
                throw SyncError.missingMediaPath
            }

            let mediaItem = MediaItem(plexItem: plexItem)

            // 2. Get audio file — use local download if available, otherwise fetch from Plex
            let tempDir = syncDirectory.appendingPathComponent(item.id, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let audioFile = tempDir.appendingPathComponent("audio", isDirectory: false)

            if let localItem = downloadManager?.items.first(where: { $0.ratingKey == item.ratingKey && $0.status == .completed }),
               let localURL = downloadManager?.localVideoURL(for: localItem) {
                // Copy from existing iOS download
                try FileManager.default.copyItem(at: localURL, to: audioFile)
            } else {
                // Download from Plex server
                guard let partPath = plexItem.media?.first?.parts.first?.key else {
                    throw SyncError.missingMediaPath
                }
                let mediaRepo = try MediaRepository(context: context)
                guard let downloadURL = mediaRepo.mediaURL(path: partPath) else {
                    throw SyncError.missingMediaPath
                }
                let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
                try FileManager.default.moveItem(at: tempURL, to: audioFile)
            }

            guard let currentIdx = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
            syncItems[currentIdx].progress = 0.5

            // 3. Get poster — use local download if available, otherwise fetch from Plex
            var posterData: Data?
            if let localItem = downloadManager?.items.first(where: { $0.ratingKey == item.ratingKey && $0.status == .completed }),
               let localPosterURL = downloadManager?.localPosterURL(for: localItem) {
                posterData = try? Data(contentsOf: localPosterURL)
            } else if let thumbPath = mediaItem.preferredThumbPath {
                let imageRepo = try ImageRepository(context: context)
                if let posterURL = imageRepo.transcodeImageURL(
                    path: thumbPath, width: 160, height: 160, minSize: 1, upscale: 1
                ) {
                    posterData = try? await URLSession.shared.data(from: posterURL).0
                }
            }

            // 4. Build metadata
            let fileSize = (try? FileManager.default.attributesOfItem(
                atPath: audioFile.path
            ))?[.size] as? Int64 ?? 0

            let downloadMetadata = DownloadedMediaMetadata(
                ratingKey: mediaItem.id,
                guid: mediaItem.guid,
                type: mediaItem.type,
                title: mediaItem.title,
                summary: mediaItem.summary,
                genres: mediaItem.genres,
                year: mediaItem.year,
                duration: mediaItem.duration,
                contentRating: mediaItem.contentRating,
                studio: mediaItem.studio,
                tagline: mediaItem.tagline,
                parentRatingKey: mediaItem.parentRatingKey,
                grandparentRatingKey: mediaItem.grandparentRatingKey,
                grandparentTitle: mediaItem.grandparentTitle,
                parentTitle: mediaItem.parentTitle,
                parentIndex: mediaItem.parentIndex,
                index: mediaItem.index,
                posterFileName: posterData != nil ? "poster.jpg" : nil,
                videoFileName: "audio",
                fileSize: fileSize,
                createdAt: Date()
            )

            let metadataJSON = try JSONEncoder().encode(downloadMetadata)
            let metadataBase64 = metadataJSON.base64EncodedString()

            var transferMetadata: [String: Any] = [
                "type": "watchSync",
                "metadata": metadataBase64,
            ]
            if let posterData {
                transferMetadata["posterData"] = posterData.base64EncodedString()
            }

            // 5. Transfer to watch
            guard let finalIdx = syncItems.firstIndex(where: { $0.id == item.id }) else { return }
            syncItems[finalIdx].status = .transferring
            syncItems[finalIdx].progress = 0.75
            persistState()

            let transfer = WCSession.default.transferFile(audioFile, metadata: transferMetadata)
            activeTransfers[item.id] = transfer

        } catch {
            if let idx = syncItems.firstIndex(where: { $0.id == item.id }) {
                syncItems[idx].status = .failed
                syncItems[idx].errorMessage = error.localizedDescription
            }
            persistState()
        }
    }

    // MARK: - Persistence

    private func persistState() {
        do {
            let data = try JSONEncoder().encode(syncItems)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {}
    }

    private func loadPersistedState() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            var loaded = try JSONDecoder().decode([WatchSyncItem].self, from: data)
            // Mark any previously active items as failed (app was killed)
            for i in loaded.indices where loaded[i].isActive {
                if loaded[i].status == .transferring {
                    // Transfer may still be in progress via WatchConnectivity
                    loaded[i].status = .queued
                } else {
                    loaded[i].status = .failed
                    loaded[i].errorMessage = "Interrupted"
                }
            }
            syncItems = loaded
        } catch {
            syncItems = []
        }
    }

    enum SyncError: LocalizedError {
        case missingMediaPath

        var errorDescription: String? {
            switch self {
            case .missingMediaPath:
                "Could not resolve media file path"
            }
        }
    }
}
