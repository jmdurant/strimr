import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.doctordurant.strimr", category: "LiveTV")

/// Simple file logger for debugging on watchOS where os_log info messages are suppressed.
enum DebugLog {
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("debug.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        logger.warning("\(message)")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

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

    func tune(channel: PlexChannel) async -> (url: URL, channelName: String)? {
        tuneError = nil
        DebugLog.clear()
        guard let dvrKey else {
            DebugLog.write("tune: no dvrKey available")
            return nil
        }

        DebugLog.write("tune: channel=\(channel.displayName) key=\(channel.tuneIdentifier) dvrKey=\(dvrKey)")

        do {
            let repo = try LiveTVRepository(context: context)

            // Step 1: Tune the channel — server allocates a tuner and creates a session
            let response = try await repo.tuneChannel(
                dvrKey: dvrKey,
                channelIdentifier: channel.tuneIdentifier
            )

            DebugLog.write("tune response: status=\(response.mediaContainer.status ?? -999) size=\(response.mediaContainer.size ?? -1) message=\(response.mediaContainer.message ?? "(none)")")

            if response.mediaContainer.status == -1 {
                let msg = response.mediaContainer.message ?? "Could not tune channel"
                DebugLog.write("tune failed: \(msg)")
                tuneError = msg
                return nil
            }

            guard let sessionPath = response.sessionPath else {
                DebugLog.write("tune: no session path in response")
                tuneError = "Failed to tune channel"
                return nil
            }

            DebugLog.write("tune session: \(sessionPath)")

            // Step 2: Call decision endpoint to warm up the transcoder
            let clientSession = UUID().uuidString
            try await repo.startLiveTVSession(sessionPath: sessionPath, session: clientSession)
            DebugLog.write("decision OK")

            // Step 3: Build the HLS stream URL
            guard let url = repo.liveTVStreamURL(sessionPath: sessionPath, session: clientSession) else {
                DebugLog.write("tune: could not build stream URL")
                tuneError = "Failed to build stream URL"
                return nil
            }

            let name = response.channelName ?? channel.displayName
            DebugLog.write("tune SUCCESS: \(url.absoluteString)")
            return (url: url, channelName: name)
        } catch {
            DebugLog.write("tune ERROR: \(error)")
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

                let endsAt = program.endsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                let np = NowPlaying(title: program.displayTitle, endsAt: endsAt)

                for media in program.media ?? [] {
                    if let callSign = media.channelCallSign {
                        map[callSign] = np
                    }
                    if let identifier = media.channelIdentifier {
                        map[identifier] = np
                    }
                    if let title = media.channelTitle {
                        map[title] = np
                    }
                }
            }
            nowPlaying = map
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
