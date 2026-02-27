import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class WatchDownloadManager: NSObject, URLSessionDownloadDelegate, AVAssetDownloadDelegate {
    static var shared: WatchDownloadManager?

    private(set) var items: [DownloadItem] = []
    private(set) var storageSummary: DownloadStorageSummary = .empty

    @ObservationIgnored private var progressByTaskIdentifier: [Int: Double] = [:]
    @ObservationIgnored private var isLoadingPersistedState = false
    @ObservationIgnored private var ignoredCompletionIDs: Set<String> = []
    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private let indexFileURL: URL
    @ObservationIgnored private var session: URLSession!
    @ObservationIgnored private var assetSession: AVAssetDownloadURLSession!
    @ObservationIgnored private var assetDownloadLocations: [Int: URL] = [:]
    @ObservationIgnored private var progressObservations: [Int: NSKeyValueObservation] = [:]

    override init() {
        downloadsDirectory = Self.buildDownloadsDirectory()
        indexFileURL = downloadsDirectory.appendingPathComponent("index.json", isDirectory: false)
        super.init()
        session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: nil
        )
        let bgConfig = URLSessionConfiguration.background(
            withIdentifier: "com.strimr.watchos.asset-downloads"
        )
        assetSession = AVAssetDownloadURLSession(
            configuration: bgConfig,
            assetDownloadDelegate: self,
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
        removeFailedItems(for: ratingKey)

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

            // Add item to the list immediately so the UI shows it as queued
            let id = UUID().uuidString
            let folderURL = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
            try createDirectoryIfNeeded(at: folderURL)

            let posterFileName = await downloadPosterIfAvailable(
                for: mediaItem,
                context: context,
                destinationFolder: folderURL
            )

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
                videoFileName: "video.movpkg",
                fileSize: nil,
                createdAt: Date()
            )

            let item = DownloadItem(
                id: id,
                status: .queued,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 0,
                taskIdentifier: nil,
                errorMessage: nil,
                metadata: metadata
            )
            items.append(item)
            persistState()

            // Warm up the transcoder so FFmpeg is already running and generating segments
            // before AVAssetDownloadURLSession requests start.m3u8.
            let transcodeRepo = try TranscodeRepository(context: context)
            let sessionID = UUID().uuidString

            guard let hlsURL = transcodeRepo.transcodeURL(
                path: metadataPath,
                session: sessionID
            ) else {
                writeDebug("[WatchDownload] failed to build HLS URL for: \(mediaItem.title)")
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx].status = .failed
                    items[idx].errorMessage = "Failed to build URL"
                    persistState()
                }
                return
            }
            writeDebug("[WatchDownload] enqueue HLS video: \(mediaItem.title), url=\(hlsURL.absoluteString.prefix(200))")
            await warmUpTranscode(hlsURL: hlsURL, title: mediaItem.title)

            let asset = AVURLAsset(url: hlsURL)
            let config = AVAssetDownloadConfiguration(asset: asset, title: mediaItem.title)
            let task = assetSession.makeAssetDownloadTask(downloadConfiguration: config)
            task.taskDescription = id

            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].status = .downloading
                items[idx].taskIdentifier = task.taskIdentifier
                persistState()
            }
            observeProgress(for: task, itemID: id)
            task.resume()
        } catch {
            writeDebug("[WatchDownload] enqueue failed: \(error)")
        }
    }

    func enqueueTrack(ratingKey: String, context: PlexAPIContext) async {
        guard !isAlreadyScheduled(for: ratingKey) else { return }
        removeFailedItems(for: ratingKey)

        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadata(
                ratingKey: ratingKey,
                params: .init(checkFiles: true)
            )
            guard let plexItem = response.mediaContainer.metadata?.first else { return }

            let mediaItem = MediaItem(plexItem: plexItem)
            guard mediaItem.type == .track else { return }

            guard let partPath = plexItem.media?.first?.parts.first?.key else { return }

            let mediaRepo = try MediaRepository(context: context)
            guard let downloadURL = mediaRepo.mediaURL(path: partPath) else { return }

            let id = UUID().uuidString
            let folderURL = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
            try createDirectoryIfNeeded(at: folderURL)

            let posterFileName = await downloadPosterIfAvailable(
                for: mediaItem,
                context: context,
                destinationFolder: folderURL,
                square: true
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
                videoFileName: "audio",
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
            writeDebug("[WatchDownload] enqueueTrack failed: \(error)")
        }
    }

    func enqueueAlbum(ratingKey: String, context: PlexAPIContext) async {
        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadataChildren(ratingKey: ratingKey)
            guard let tracks = response.mediaContainer.metadata else { return }

            for track in tracks {
                let trackItem = MediaItem(plexItem: track)
                guard trackItem.type == .track else { continue }
                await enqueueTrack(ratingKey: trackItem.id, context: context)
            }
        } catch {
            writeDebug("[WatchDownload] enqueueAlbum failed: \(error)")
        }
    }

    func enqueueSeason(ratingKey: String, context: PlexAPIContext) async {
        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadataChildren(ratingKey: ratingKey)
            let episodes = (response.mediaContainer.metadata ?? []).filter { $0.type == .episode }
            for episode in episodes {
                await enqueueItem(ratingKey: episode.ratingKey, context: context)
            }
        } catch {
            writeDebug("[WatchDownload] enqueueSeason failed: \(error)")
        }
    }

    func savePlaybackPosition(_ position: TimeInterval, forRatingKey ratingKey: String) {
        guard let index = items.firstIndex(where: { $0.ratingKey == ratingKey }) else { return }
        items[index].metadata.viewOffset = position
        items[index].metadata.lastViewedAt = Date()
        persistState()
    }

    private(set) var dismissedItemIDs: Set<String> = []

    func clearList() {
        for item in items where !item.status.isActive {
            dismissedItemIDs.insert(item.id)
        }
    }

    /// Items visible in the Downloads tab (excludes dismissed).
    var visibleItems: [DownloadItem] {
        items.filter { !dismissedItemIDs.contains($0.id) }
    }

    func delete(_ item: DownloadItem) {
        if let taskIdentifier = item.taskIdentifier {
            ignoredCompletionIDs.insert(item.id)
            progressObservations.removeValue(forKey: taskIdentifier)
            session.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
            }
            assetSession.getAllTasks { tasks in
                tasks.first { $0.taskIdentifier == taskIdentifier }?.cancel()
            }
        }

        // Remove asset download at system-provided location
        if let assetURLString = item.metadata.assetLocation,
           let assetURL = URL(string: assetURLString) {
            if FileManager.default.fileExists(atPath: assetURL.path) {
                try? FileManager.default.removeItem(at: assetURL)
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

        // Asset downloads (.movpkg) stay at the system-provided location
        if let assetPath = item.metadata.assetLocation {
            let fullPath: String
            if assetPath.hasPrefix("/Library/") || assetPath.hasPrefix("/tmp/") {
                // Relative path (new format) — prepend current home directory
                fullPath = NSHomeDirectory() + assetPath
            } else {
                // Legacy: file:// URL or absolute path with potentially stale container UUID.
                let rawPath: String
                if let url = URL(string: assetPath) {
                    rawPath = url.path
                } else {
                    rawPath = assetPath
                }
                writeDebug("[localVideoURL] rawPath=\(rawPath)")

                // Try as-is first
                if FileManager.default.fileExists(atPath: rawPath) {
                    return URL(fileURLWithPath: rawPath)
                }

                // Extract the relative portion after /Application/<UUID>/
                if let range = rawPath.range(of: #"/Application/[A-Fa-f0-9\-]+/"#, options: .regularExpression) {
                    let relativePath = String(rawPath[range.upperBound...])
                    fullPath = NSHomeDirectory() + "/" + relativePath
                    writeDebug("[localVideoURL] re-rooted=\(fullPath)")
                } else {
                    writeDebug("[localVideoURL] no regex match")
                    return nil
                }
            }
            let exists = FileManager.default.fileExists(atPath: fullPath)
            writeDebug("[localVideoURL] exists=\(exists), path=\(fullPath)")
            return exists ? URL(fileURLWithPath: fullPath) : nil
        }

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
            viewOffset: item.metadata.viewOffset,
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
        if task is AVAssetDownloadTask {
            Task { @MainActor in
                if let error {
                    failAssetDownload(task: task, error: error)
                } else {
                    completeAssetDownload(task: task)
                }
            }
            return
        }
        guard let error else { return }
        Task { @MainActor in
            failDownload(task: task, error: error)
        }
    }

    // MARK: - AVAssetDownloadDelegate

    nonisolated func urlSession(
        _: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        willDownloadTo location: URL
    ) {
        Task { @MainActor in
            assetDownloadLocations[assetDownloadTask.taskIdentifier] = location
            writeDebug("[WatchDownload] willDownloadTo: \(location.path)")
        }
    }

    // MARK: - TLS Trust (for .plex.direct)

    nonisolated func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        let method = challenge.protectionSpace.authenticationMethod
        writeDebug("[WatchDownload] TLS challenge: host=\(host), method=\(method)")
        if method == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           host.hasSuffix(".plex.direct")
        {
            writeDebug("[WatchDownload] TLS: trusting .plex.direct")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // MARK: - Transcode Warmup

    /// Fetch start.m3u8 to create the transcode session, then fetch the variant index.m3u8
    /// to kick off FFmpeg, and poll until the first segment is ready. After this returns,
    /// AVAssetDownloadURLSession can safely request start.m3u8 — FFmpeg is already running
    /// and will quickly regenerate segments after the server's directory cleanup.
    @discardableResult
    private func warmUpTranscode(hlsURL: URL, title: String) async -> Bool {
        do {
            // 1. Fetch master playlist — creates transcode session on the server
            let (masterData, masterResp) = try await PlexURLSession.shared.data(from: hlsURL)
            let masterStatus = (masterResp as? HTTPURLResponse)?.statusCode ?? -1
            guard masterStatus == 200,
                  let masterBody = String(data: masterData, encoding: .utf8) else {
                writeDebug("[WatchDownload] warmup: master m3u8 failed status=\(masterStatus) for \(title)")
                return false
            }

            // 2. Parse the variant playlist URL from the master
            let lines = masterBody.components(separatedBy: "\n")
            guard let variantLine = lines.first(where: { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                writeDebug("[WatchDownload] warmup: no variant URL in master for \(title)")
                return false
            }
            guard let variantURL = URL(string: variantLine.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: hlsURL) else {
                writeDebug("[WatchDownload] warmup: couldn't resolve variant URL for \(title)")
                return false
            }
            writeDebug("[WatchDownload] warmup: variant URL = \(variantURL.absoluteString.prefix(200))")

            // 3. Fetch variant playlist — this starts FFmpeg on the server
            let (variantData, variantResp) = try await PlexURLSession.shared.data(from: variantURL)
            let variantStatus = (variantResp as? HTTPURLResponse)?.statusCode ?? -1
            guard variantStatus == 200,
                  let variantBody = String(data: variantData, encoding: .utf8) else {
                writeDebug("[WatchDownload] warmup: variant m3u8 failed status=\(variantStatus) for \(title)")
                return false
            }

            // 4. Find the first .ts segment URL
            let segLines = variantBody.components(separatedBy: "\n")
            guard let segLine = segLines.first(where: {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("#") && !t.isEmpty && t.hasSuffix(".ts")
            }) else {
                writeDebug("[WatchDownload] warmup: no .ts segment in variant for \(title)")
                return false
            }
            guard let segURL = URL(string: segLine.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: variantURL) else {
                return false
            }

            // 5. Poll until the first segment is available (transcoder needs time to produce it)
            writeDebug("[WatchDownload] warmup: polling first segment for \(title)")
            for attempt in 1...20 {
                var req = URLRequest(url: segURL)
                req.httpMethod = "HEAD"
                let (_, resp) = try await PlexURLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                if status == 200 {
                    writeDebug("[WatchDownload] warmup: segment ready after \(attempt) poll(s) for \(title)")
                    return true
                }
                writeDebug("[WatchDownload] warmup: poll \(attempt) status=\(status) for \(title)")
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            }
            writeDebug("[WatchDownload] warmup: timed out for \(title), proceeding anyway")
            return true
        } catch {
            writeDebug("[WatchDownload] warmup failed: \(error)")
            return false
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
        destinationFolder: URL,
        square: Bool = false
    ) async -> String? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        guard let thumbPath = mediaItem.preferredThumbPath else { return nil }
        let height: Int = square ? 160 : 240
        guard let posterURL = imageRepository.transcodeImageURL(path: thumbPath, width: 160, height: height)
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

    private func removeFailedItems(for ratingKey: String) {
        let failedItems = items.filter { $0.ratingKey == ratingKey && $0.status == .failed }
        for item in failedItems {
            let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
            if FileManager.default.fileExists(atPath: folderURL.path) {
                try? FileManager.default.removeItem(at: folderURL)
            }
        }
        items.removeAll { $0.ratingKey == ratingKey && $0.status == .failed }
        if !failedItems.isEmpty { persistState() }
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

        // Validate HTTP response status
        if let httpResponse = task.response as? HTTPURLResponse {
            writeDebug("[WatchDownload] HTTP \(httpResponse.statusCode) for: \(item.metadata.title)")
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 400 {
                try? FileManager.default.removeItem(at: stagedLocation)
                items[index].status = .failed
                items[index].taskIdentifier = nil
                items[index].errorMessage = "Server error (HTTP \(httpResponse.statusCode))"
                persistState()
                writeDebug("[WatchDownload] failed HTTP \(httpResponse.statusCode): \(item.metadata.title)")
                return
            }
        }

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

            // Validate minimum file size — anything under 10KB is an error response, not media
            if fileSize < 10_000 {
                try? FileManager.default.removeItem(at: destination)
                items[index].status = .failed
                items[index].taskIdentifier = nil
                items[index].errorMessage = "Download failed (received \(fileSize) bytes — not a valid media file)"
                persistState()
                writeDebug("[WatchDownload] failed: \(item.metadata.title), too small (\(fileSize) bytes)")
                return
            }

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

    private func completeAssetDownload(task: URLSessionTask) {
        progressObservations.removeValue(forKey: task.taskIdentifier)
        guard let index = itemIndex(for: task) else { return }
        let item = items[index]

        guard let sourceURL = assetDownloadLocations.removeValue(forKey: task.taskIdentifier) else {
            writeDebug("[WatchDownload] asset complete but no source URL for: \(item.metadata.title)")
            items[index].status = .failed
            items[index].taskIdentifier = nil
            items[index].errorMessage = "Download location unknown"
            persistState()
            return
        }

        // Apple docs: "Do not move the saved asset." — keep it at the system-provided location.
        // Store relative path (from home directory) so it survives container UUID changes on reinstall.
        let fileSize = Self.directorySize(at: sourceURL)
        let homePath = NSHomeDirectory()
        let relativePath = sourceURL.path.hasPrefix(homePath)
            ? String(sourceURL.path.dropFirst(homePath.count))
            : sourceURL.path

        items[index].status = .completed
        items[index].progress = 1
        items[index].bytesWritten = fileSize
        items[index].totalBytes = fileSize
        items[index].taskIdentifier = nil
        items[index].errorMessage = nil
        items[index].metadata.videoFileName = "video.movpkg"
        items[index].metadata.assetLocation = relativePath
        items[index].metadata.fileSize = fileSize

        persistState()
        refreshStorageSummary()
        writeDebug("[WatchDownload] asset completed: \(item.metadata.title), size=\(fileSize), location=\(sourceURL.path)")
    }

    private func failAssetDownload(task: URLSessionTask, error: Error) {
        progressObservations.removeValue(forKey: task.taskIdentifier)
        assetDownloadLocations.removeValue(forKey: task.taskIdentifier)

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
        writeDebug("[WatchDownload] asset failed: \(error)")
    }

    private func observeProgress(for task: AVAssetDownloadTask, itemID: String) {
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let index = self.items.firstIndex(where: { $0.id == itemID })
                else { return }
                let fraction = progress.fractionCompleted
                let previous = self.progressByTaskIdentifier[task.taskIdentifier] ?? -1
                guard fraction - previous >= 0.01 || fraction >= 1 else { return }
                self.progressByTaskIdentifier[task.taskIdentifier] = fraction
                self.items[index].progress = fraction
                self.items[index].status = .downloading
                self.persistState()
            }
        }
        progressObservations[task.taskIdentifier] = observation
    }

    private static func directorySize(at url: URL) -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
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
