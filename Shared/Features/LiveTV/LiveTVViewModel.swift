import Foundation
import Observation

@MainActor
@Observable
final class LiveTVViewModel {
    private(set) var channels: [PlexChannel] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dvrKey: String?

    /// Now-playing info keyed by channel identifier (e.g. channel call sign or identifier).
    private(set) var nowPlaying: [String: NowPlaying] = [:]

    private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
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

            let channelResponse = try await repo.getChannels(dvrKey: dvr.key)
            channels = channelResponse.mediaContainer.metadata ?? []

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
        // Try matching by title (channel name), key, and ratingKey
        nowPlaying[channel.displayName]
            ?? nowPlaying[channel.key]
            ?? channel.ratingKey.flatMap { nowPlaying[$0] }
    }

    func tune(channel: PlexChannel) async -> (url: URL, channelName: String)? {
        guard let dvrKey else { return nil }

        do {
            let repo = try LiveTVRepository(context: context)
            let response = try await repo.tuneChannel(dvrKey: dvrKey, channelKey: channel.key)

            guard let metadata = response.mediaContainer.metadata?.first,
                  let media = metadata.media?.first,
                  let part = media.part?.first,
                  let partKey = part.key
            else {
                errorMessage = "Failed to tune channel"
                return nil
            }

            guard let url = repo.streamURL(partKey: partKey) else {
                errorMessage = "Failed to build stream URL"
                return nil
            }

            let name = media.channelTitle ?? media.channelCallSign ?? channel.displayName
            return (url: url, channelName: name)
        } catch {
            errorMessage = "Tune failed: \(error.localizedDescription)"
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

    // MARK: - Private

    private func loadNowPlaying(repo: LiveTVRepository) async {
        do {
            guard let epgKey = try await repo.getEPGProviderKey() else { return }
            let grid = try await repo.getNowPlaying(epgKey: epgKey)

            var map: [String: NowPlaying] = [:]
            for program in grid.mediaContainer.metadata ?? [] {
                let endsAt = program.endsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                let np = NowPlaying(title: program.displayTitle, endsAt: endsAt)

                // Index by every channel identifier we can find on this program
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
            // EPG is best-effort — don't surface errors for it
        }
    }
}

// MARK: - LiveStreamInfo

struct LiveStreamInfo: Identifiable {
    let id = UUID()
    let url: URL
    let channelName: String
}
