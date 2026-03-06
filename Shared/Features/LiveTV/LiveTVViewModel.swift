import Foundation
import Observation

@MainActor
@Observable
final class LiveTVViewModel {
    private(set) var channels: [PlexChannel] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// Error message shown as an alert after a failed tune attempt.
    var tuneError: String?
    /// Error message shown after a failed recording attempt.
    var recordingError: String?
    private(set) var dvrKey: String?
    private(set) var lineup: String?

    /// Now-playing info keyed by channel identifier / call sign / title.
    private(set) var nowPlaying: [String: NowPlaying] = [:]

    /// EPG grid rows for the guide view.
    private(set) var epgRows: [EPGGridRow] = []
    /// The time window currently loaded in the EPG grid.
    private(set) var epgTimeWindow: (start: Date, end: Date)?
    private(set) var isLoadingGrid = false

    var settingsManager: SettingsManager?

    private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
    }

    /// Channels sorted with favorites first, preserving server order within each group.
    var sortedChannels: [PlexChannel] {
        guard let favoriteIds = settingsManager?.interface.favoriteChannelIds,
              !favoriteIds.isEmpty else { return channels }
        let favoriteSet = Set(favoriteIds)
        let favorites = channels.filter { favoriteSet.contains($0.id) }
        let rest = channels.filter { !favoriteSet.contains($0.id) }
        return favorites + rest
    }

    func load() async {
        guard channels.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let repo = try LiveTVRepository(context: context)

            let dvrResponse = try await repo.getDVRs()
            guard let dvr = dvrResponse.mediaContainer.dvr?.first else {
                errorMessage = "No DVR configured on this server"
                return
            }

            dvrKey = dvr.key

            guard let lineupURI = dvr.lineup else {
                errorMessage = "No lineup configured on this DVR"
                return
            }
            lineup = lineupURI

            let channelResponse = try await repo.getChannels(lineup: lineupURI)
            channels = channelResponse.channels

            if channels.isEmpty {
                errorMessage = "No channels found"
            } else {
                await loadNowPlaying(repo: repo)
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Look up what's currently on a given channel.
    func nowPlaying(for channel: PlexChannel) -> NowPlaying? {
        if let id = channel.identifier, let np = nowPlaying[id] { return np }
        if let cs = channel.callSign, let np = nowPlaying[cs] { return np }
        if let t = channel.title, let np = nowPlaying[t] { return np }
        if let k = channel.key, let np = nowPlaying[k] { return np }
        return nil
    }

    /// Look up the currently airing EPG program for a channel from grid data.
    func airingProgram(for channel: PlexChannel) -> EPGGridProgram? {
        guard let row = epgRows.first(where: { $0.channel.id == channel.id }) else { return nil }
        let now = Date()
        return row.programs.first(where: { $0.beginsAt <= now && $0.endsAt >= now })
    }

    func tune(channel: PlexChannel) async -> (url: URL, channelName: String, programTitle: String?)? {
        tuneError = nil
        AppLogger.clearFileLog()
        guard let dvrKey else {
            AppLogger.fileLog("tune: no dvrKey available", logger: AppLogger.liveTV)
            return nil
        }

        AppLogger.fileLog("tune: channel=\(channel.displayName) key=\(channel.tuneIdentifier) dvrKey=\(dvrKey)", logger: AppLogger.liveTV)

        do {
            let repo = try LiveTVRepository(context: context)

            // Step 1: Tune the channel — server allocates a tuner and creates a session
            let response = try await repo.tuneChannel(
                dvrKey: dvrKey,
                channelIdentifier: channel.tuneIdentifier
            )

            AppLogger.fileLog("tune response: status=\(response.mediaContainer.status ?? -999) size=\(response.mediaContainer.size ?? -1) message=\(response.mediaContainer.message ?? "(none)")", logger: AppLogger.liveTV)

            if response.mediaContainer.status == -1 {
                let msg = response.mediaContainer.message ?? "Could not tune channel"
                AppLogger.fileLog("tune failed: \(msg)", logger: AppLogger.liveTV)
                tuneError = msg
                return nil
            }

            guard let sessionPath = response.sessionPath else {
                AppLogger.fileLog("tune: no session path in response", logger: AppLogger.liveTV)
                tuneError = "Failed to tune channel"
                return nil
            }

            AppLogger.fileLog("tune session: \(sessionPath)", logger: AppLogger.liveTV)

            // Step 2: Call decision endpoint to warm up the transcoder
            let clientSession = UUID().uuidString
            let quality = settingsManager?.playback.streamQuality ?? .q720
            try await repo.startLiveTVSession(sessionPath: sessionPath, session: clientSession, quality: quality)
            AppLogger.fileLog("decision OK (quality=\(quality.resolution))", logger: AppLogger.liveTV)

            // Step 3: Build the HLS stream URL
            guard let url = repo.liveTVStreamURL(sessionPath: sessionPath, session: clientSession, quality: quality) else {
                AppLogger.fileLog("tune: could not build stream URL", logger: AppLogger.liveTV)
                tuneError = "Failed to build stream URL"
                return nil
            }

            let programTitle = response.channelName
            AppLogger.fileLog("tune SUCCESS: \(url.absoluteString)", logger: AppLogger.liveTV)
            return (url: url, channelName: channel.displayName, programTitle: programTitle)
        } catch {
            AppLogger.fileLog("tune ERROR: \(error)", logger: AppLogger.liveTV)
            tuneError = "Tuner device is offline or unreachable"
            return nil
        }
    }

    /// Check whether the connected server has at least one DVR configured.
    func checkAvailability() async -> Bool {
        do {
            let repo = try LiveTVRepository(context: context)
            let response = try await repo.getDVRs()
            return response.mediaContainer.dvr?.isEmpty == false
        } catch {
            return false
        }
    }

    /// Schedule a DVR recording for a non-airing program.
    func scheduleRecording(program: EPGGridProgram) async -> Bool {
        recordingError = nil
        guard let ratingKey = program.ratingKey else {
            recordingError = "Program cannot be recorded"
            return false
        }

        do {
            let repo = try LiveTVRepository(context: context)
            let template = try await repo.getRecordingTemplate(key: "/library/metadata/\(ratingKey)")
            guard let parameters = template.mediaContainer.mediaSubscription?.first?.parameters else {
                recordingError = "No recording template available"
                return false
            }
            try await repo.scheduleRecording(parameters: parameters)
            return true
        } catch {
            recordingError = "Failed to schedule recording"
            return false
        }
    }

    /// Load a 3-hour EPG grid window starting at the current hour.
    func loadEPGGrid() async {
        guard !channels.isEmpty else { return }
        isLoadingGrid = true
        defer { isLoadingGrid = false }

        do {
            let repo = try LiveTVRepository(context: context)
            guard let epgKey = try await repo.getEPGProviderKey() else { return }

            let now = Date()
            let calendar = Calendar.current
            let windowStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let windowEnd = windowStart.addingTimeInterval(3 * 60 * 60) // 3 hours forward
            let from = Int(windowStart.timeIntervalSince1970)
            let to = Int(windowEnd.timeIntervalSince1970)

            let grid = try await repo.getEPGGrid(epgKey: epgKey, from: from, to: to)
            let programs = grid.mediaContainer.metadata ?? []

            // Group programs by channel identifier, reading times from Media objects
            var channelPrograms: [String: [EPGGridProgram]] = [:]
            for program in programs {
                for media in program.media ?? [] {
                    let beginsAt: Date = media.beginsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? windowStart
                    let endsAt: Date = media.endsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? windowEnd
                    let gridProgram = EPGGridProgram(
                        title: program.displayTitle,
                        beginsAt: beginsAt,
                        endsAt: endsAt,
                        ratingKey: program.ratingKey
                    )
                    if let id = media.channelIdentifier {
                        channelPrograms[id, default: []].append(gridProgram)
                    }
                    if let cs = media.channelCallSign {
                        channelPrograms[cs, default: []].append(gridProgram)
                    }
                    if let t = media.channelTitle {
                        channelPrograms[t, default: []].append(gridProgram)
                    }
                }
            }

            // Build rows matching the channel order (favorites first), deduplicating by time
            var rows: [EPGGridRow] = []
            for channel in sortedChannels {
                let matches = findPrograms(for: channel, in: channelPrograms)
                let sorted = matches.sorted { $0.beginsAt < $1.beginsAt }
                // Remove duplicates (same start time)
                var deduped: [EPGGridProgram] = []
                for program in sorted {
                    if let last = deduped.last, last.beginsAt == program.beginsAt {
                        continue
                    }
                    deduped.append(program)
                }
                rows.append(EPGGridRow(channel: channel, programs: deduped))
            }

            epgRows = rows
            epgTimeWindow = (start: windowStart, end: windowEnd)
        } catch {
            guard !Task.isCancelled else { return }
        }
    }

    // MARK: - Private

    /// Find programs for a channel by trying all known identifiers.
    private func findPrograms(for channel: PlexChannel, in map: [String: [EPGGridProgram]]) -> [EPGGridProgram] {
        if let id = channel.identifier, let programs = map[id] { return programs }
        if let cs = channel.callSign, let programs = map[cs] { return programs }
        if let t = channel.title, let programs = map[t] { return programs }
        if let k = channel.key, let programs = map[k] { return programs }
        return []
    }

    private func loadNowPlaying(repo: LiveTVRepository) async {
        do {
            guard let epgKey = try await repo.getEPGProviderKey() else { return }
            let grid = try await repo.getNowPlaying(epgKey: epgKey)

            let now = Int(Date().timeIntervalSince1970)
            var map: [String: NowPlaying] = [:]
            for program in grid.mediaContainer.metadata ?? [] {
                if let begins = program.beginsAt, begins > now { continue }
                if let ends = program.endsAt, ends < now { continue }

                // Check program-level endsAt first, then fall back to media-level
                let programEndsAt: Date? = program.endsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    ?? program.media?.compactMap({ $0.endsAt }).first.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                let np = NowPlaying(title: program.displayTitle, endsAt: programEndsAt)

                for media in program.media ?? [] {
                    // Also use media-level endsAt if it's more specific
                    let mediaEndsAt = media.endsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    let mediaNp = mediaEndsAt != nil ? NowPlaying(title: program.displayTitle, endsAt: mediaEndsAt) : np

                    if let callSign = media.channelCallSign {
                        map[callSign] = mediaNp
                    }
                    if let identifier = media.channelIdentifier {
                        map[identifier] = mediaNp
                    }
                    if let title = media.channelTitle {
                        map[title] = mediaNp
                    }
                }
            }
            nowPlaying = map

            // Also load EPG grid in background so airingProgram(for:) works from list view
            if epgRows.isEmpty {
                await loadEPGGrid()
            }
        } catch {
            // Silently fail — now-playing is supplementary
        }
    }
}

// MARK: - LiveStreamInfo

struct LiveStreamInfo: Identifiable {
    let id = UUID()
    let url: URL
    let channelName: String
    var programTitle: String?
    var programEndsAt: Date?
}

// MARK: - EPG Grid Types

struct EPGGridRow: Identifiable {
    let channel: PlexChannel
    let programs: [EPGGridProgram]

    var id: String { channel.id }
}

struct EPGGridProgram: Identifiable {
    let id = UUID()
    let title: String
    let beginsAt: Date
    let endsAt: Date
    let ratingKey: String?
}
