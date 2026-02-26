import Foundation
import Observation

@MainActor
@Observable
final class LiveTVViewModel {
    private(set) var channels: [PlexChannel] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var dvrKey: String?

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
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
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
}
