import Foundation

@MainActor
final class WatchSyncReceiver {
    private let downloadManager: WatchDownloadManager

    init(downloadManager: WatchDownloadManager) {
        self.downloadManager = downloadManager
    }

    func handleReceivedFile(_ file: URL, metadata: [String: Any]) {
        guard let type = metadata["type"] as? String, type == "watchSync" else { return }

        guard let metadataBase64 = metadata["metadata"] as? String,
              let metadataData = Data(base64Encoded: metadataBase64),
              var downloadMetadata = try? JSONDecoder().decode(
                  DownloadedMediaMetadata.self, from: metadataData
              ) else {
            debugPrint("[WatchSync] Failed to decode metadata from transfer")
            return
        }

        let downloadsDir = Self.downloadsDirectory()
        let id = UUID().uuidString
        let folderURL = downloadsDir.appendingPathComponent(id, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            debugPrint("[WatchSync] Failed to create folder: \(error)")
            return
        }

        // Move audio file from WCSession temp location
        let audioDestination = folderURL.appendingPathComponent("audio", isDirectory: false)
        do {
            try FileManager.default.moveItem(at: file, to: audioDestination)
        } catch {
            debugPrint("[WatchSync] Failed to move audio file: \(error)")
            try? FileManager.default.removeItem(at: folderURL)
            return
        }

        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: audioDestination.path
        ))?[.size] as? Int64 ?? 0

        // Save poster if present
        if let posterBase64 = metadata["posterData"] as? String,
           let posterData = Data(base64Encoded: posterBase64), !posterData.isEmpty {
            let posterDest = folderURL.appendingPathComponent("poster.jpg", isDirectory: false)
            try? posterData.write(to: posterDest, options: .atomic)
            downloadMetadata.posterFileName = "poster.jpg"
        }

        downloadMetadata.videoFileName = "audio"
        downloadMetadata.fileSize = fileSize
        downloadMetadata.createdAt = Date()

        let item = DownloadItem(
            id: id,
            status: .completed,
            progress: 1,
            bytesWritten: fileSize,
            totalBytes: fileSize,
            taskIdentifier: nil,
            errorMessage: nil,
            metadata: downloadMetadata
        )

        downloadManager.insertSyncedItem(item)
        debugPrint("[WatchSync] Received and stored: \(downloadMetadata.title)")
    }

    private static func downloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }
}
