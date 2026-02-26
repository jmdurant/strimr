import Foundation
import Observation

@MainActor
@Observable
final class WatchDownloadManager: NSObject, URLSessionDownloadDelegate {
    static var shared: WatchDownloadManager?

    private(set) var items: [DownloadItem] = []
    private(set) var storageSummary: DownloadStorageSummary = .empty

    @ObservationIgnored private var progressByTaskIdentifier: [Int: Double] = [:]
    @ObservationIgnored private var isLoadingPersistedState = false
    @ObservationIgnored private var ignoredCompletionIDs: Set<String> = []
    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private let indexFileURL: URL
    @ObservationIgnored private var session: URLSession!

    override init() {
        downloadsDirectory = Self.buildDownloadsDirectory()
        indexFileURL = downloadsDirectory.appendingPathComponent("index.json", isDirectory: false)
        super.init()
        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
        configureStorage()
        loadPersistedState()
        refreshStorageSummary()
        Self.shared = self
    }

    // MARK: - Public

    func enqueueItem(ratingKey: String, context: PlexAPIContext) async {
        guard !isAlreadyScheduled(for: ratingKey) else { return }

        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadata(
                ratingKey: ratingKey,
                params: .init(checkFiles: true)
            )
            guard let plexItem = response.mediaContainer.metadata?.first else { return }

            let mediaItem = MediaItem(plexItem: plexItem)
            guard mediaItem.type == .movie || mediaItem.type == .episode else { return }
            let metadataPath = plexItem.key

            let transcodeRepo = try TranscodeRepository(context: context)
            let sessionID = UUID().uuidString
            guard let downloadURL = transcodeRepo.transcodeDownloadURL(
                path: metadataPath,
                session: sessionID
            ) else { return }

            let id = UUID().uuidString
            let folderURL = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
            try createDirectoryIfNeeded(at: folderURL)

            let posterFileName = await downloadPosterIfAvailable(
                for: mediaItem,
                context: context,
                destinationFolder: folderURL
            )

            let request = URLRequest(url: downloadURL)
            let task = session.downloadTask(with: request)
            task.taskDescription = id

            let metadata = DownloadedMediaMetadata(
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
                posterFileName: posterFileName,
                videoFileName: "video",
                fileSize: nil,
                createdAt: Date()
            )

            let item = DownloadItem(
                id: id,
                status: .downloading,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 0,
                taskIdentifier: task.taskIdentifier,
                errorMessage: nil,
                metadata: metadata
            )
            items.append(item)
            persistState()
            task.resume()
        } catch {
            writeDebug("[WatchDownload] enqueue failed: \(error)")
        }
    }

    func delete(_ item: DownloadItem) {
        if let taskIdentifier = item.taskIdentifier {
            ignoredCompletionIDs.insert(item.id)
            session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
            }
        }

        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.removeItem(at: folderURL)
        }

        items.removeAll { $0.id == item.id }
        progressByTaskIdentifier.removeValue(forKey: item.taskIdentifier ?? -1)
        persistState()
        refreshStorageSummary()
    }

    func localVideoURL(for item: DownloadItem) -> URL? {
        guard item.status == .completed else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(item.metadata.videoFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func localPosterURL(for item: DownloadItem) -> URL? {
        guard let posterFileName = item.metadata.posterFileName else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(posterFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func localMediaItem(for item: DownloadItem) -> MediaItem {
        MediaItem(
            id: item.metadata.ratingKey,
            guid: item.metadata.guid,
            summary: item.metadata.summary,
            title: item.metadata.title,
            type: item.metadata.type,
            parentRatingKey: item.metadata.parentRatingKey,
            grandparentRatingKey: item.metadata.grandparentRatingKey,
            genres: item.metadata.genres,
            year: item.metadata.year,
            duration: item.metadata.duration,
            videoResolution: nil,
            rating: nil,
            contentRating: item.metadata.contentRating,
            studio: item.metadata.studio,
            tagline: item.metadata.tagline,
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: item.metadata.grandparentTitle,
            parentTitle: item.metadata.parentTitle,
            parentIndex: item.metadata.parentIndex,
            index: item.metadata.index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil
        )
    }

    func downloadStatus(for ratingKey: String) -> DownloadItem? {
        items.first { $0.ratingKey == ratingKey }
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard totalBytesExpectedToWrite > 0 else { return }
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let previousProgress = progressByTaskIdentifier[downloadTask.taskIdentifier] ?? -1
            guard progress - previousProgress >= 0.01 || progress == 1 else { return }
            progressByTaskIdentifier[downloadTask.taskIdentifier] = progress

            updateItem({ item in
                item.status = .downloading
                item.progress = progress
                item.bytesWritten = totalBytesWritten
                item.totalBytes = totalBytesExpectedToWrite
            }, matchingTask: downloadTask)
            persistState()
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let stagedURL = try Self.stageDownloadFile(at: location)
            Task { @MainActor in
                await completeDownload(task: downloadTask, stagedLocation: stagedURL)
            }
        } catch {
            Task { @MainActor in
                failDownload(task: downloadTask, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return }
        Task { @MainActor in
            failDownload(task: task, error: error)
        }
    }

    // MARK: - TLS Trust (for .plex.direct)

    nonisolated func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           challenge.protectionSpace.host.hasSuffix(".plex.direct")
        {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Private

    private static func buildDownloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    private func configureStorage() {
        do {
            try createDirectoryIfNeeded(at: downloadsDirectory)
        } catch {
            writeDebug("[WatchDownload] storage setup failed: \(error)")
        }
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
    }

    private func downloadPosterIfAvailable(
        for mediaItem: MediaItem,
        context: PlexAPIContext,
        destinationFolder: URL
    ) async -> String? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        guard let thumbPath = mediaItem.preferredThumbPath else { return nil }
        guard let posterURL = imageRepository.transcodeImageURL(path: thumbPath, width: 160, height: 240)
        else { return nil }

        do {
            let (data, _) = try await PlexURLSession.shared.data(from: posterURL)
            guard !data.isEmpty else { return nil }
            let fileName = "poster.jpg"
            let destination = destinationFolder.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: destination, options: .atomic)
            return fileName
        } catch {
            return nil
        }
    }

    private func isAlreadyScheduled(for ratingKey: String) -> Bool {
        items.contains { $0.ratingKey == ratingKey && $0.status != .failed }
    }

    private func persistState() {
        guard !isLoadingPersistedState else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {}
    }

    private func loadPersistedState() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        isLoadingPersistedState = true
        defer { isLoadingPersistedState = false }

        do {
            let data = try Data(contentsOf: indexFileURL)
            var loaded = try JSONDecoder().decode([DownloadItem].self, from: data)
            // Mark any previously active downloads as failed (app was killed)
            for i in loaded.indices where loaded[i].status.isActive {
                loaded[i].status = .failed
                loaded[i].errorMessage = "Interrupted"
                loaded[i].taskIdentifier = nil
            }
            items = loaded
        } catch {
            items = []
        }
    }

    func refreshStorageSummary() {
        let downloadsBytes = items.reduce(into: Int64(0)) { result, item in
            if item.status == .completed {
                result += item.metadata.fileSize ?? 0
            }
        }

        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let totalBytes = (attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let freeBytes = (attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0

        storageSummary = DownloadStorageSummary(
            totalBytes: totalBytes,
            usedBytes: max(0, totalBytes - freeBytes),
            availableBytes: freeBytes,
            downloadsBytes: downloadsBytes
        )
    }

    private func updateItem(_ transform: (inout DownloadItem) -> Void, matchingTask task: URLSessionTask) {
        guard let index = itemIndex(for: task) else { return }
        transform(&items[index])
    }

    private func itemIndex(for task: URLSessionTask) -> Int? {
        if let description = task.taskDescription,
           let idx = items.firstIndex(where: { $0.id == description })
        {
            return idx
        }
        return items.firstIndex(where: { $0.taskIdentifier == task.taskIdentifier })
    }

    private func completeDownload(task: URLSessionDownloadTask, stagedLocation: URL) async {
        guard let index = itemIndex(for: task) else { return }
        let item = items[index]
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let suggestedName = task.response?.suggestedFilename ?? "video"
        let destination = folderURL.appendingPathComponent(suggestedName, isDirectory: false)

        do {
            try createDirectoryIfNeeded(at: folderURL)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: stagedLocation, to: destination)

            let fileAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0

            items[index].status = .completed
            items[index].progress = 1
            items[index].bytesWritten = fileSize
            items[index].totalBytes = fileSize
            items[index].taskIdentifier = nil
            items[index].errorMessage = nil
            items[index].metadata.videoFileName = destination.lastPathComponent
            items[index].metadata.fileSize = fileSize

            persistState()
            refreshStorageSummary()
            writeDebug("[WatchDownload] completed: \(item.metadata.title), size=\(fileSize)")
        } catch {
            items[index].status = .failed
            items[index].taskIdentifier = nil
            items[index].errorMessage = error.localizedDescription
            persistState()
            writeDebug("[WatchDownload] move failed: \(error)")
        }
    }

    private func failDownload(task: URLSessionTask, error: Error) {
        guard let index = itemIndex(for: task) else { return }
        let itemID = items[index].id
        guard !ignoredCompletionIDs.contains(itemID) else {
            ignoredCompletionIDs.remove(itemID)
            return
        }

        items[index].status = .failed
        items[index].taskIdentifier = nil
        items[index].errorMessage = error.localizedDescription
        persistState()
        writeDebug("[WatchDownload] failed: \(error)")
    }

    private nonisolated static func stageDownloadFile(at location: URL) throws -> URL {
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("strimr-download-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let stagedURL = stagingDir.appendingPathComponent(UUID().uuidString, isDirectory: false)
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            try FileManager.default.removeItem(at: stagedURL)
        }
        try FileManager.default.moveItem(at: location, to: stagedURL)
        return stagedURL
    }
}
