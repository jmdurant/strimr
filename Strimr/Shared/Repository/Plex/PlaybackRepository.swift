import Foundation

final class PlaybackRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authToken else {
            throw PlexAPIError.missingAuthToken
        }

        self.context = context
        self.network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }

    func setPreferredStreams(
        partId: Int,
        audioStreamId: Int? = nil,
        subtitleStreamId: Int? = nil,
        applyToAllParts: Bool = true
    ) async throws {
        var queryItems: [URLQueryItem] = []

        if let audioStreamId {
            queryItems.append(URLQueryItem(name: "audioStreamID", value: String(audioStreamId)))
        }

        if let subtitleStreamId {
            queryItems.append(URLQueryItem(name: "subtitleStreamID", value: String(subtitleStreamId)))
        }

        queryItems.append(URLQueryItem(name: "allParts", value: applyToAllParts ? "1" : "0"))

        try await network.send(
            path: "/library/parts/\(partId)",
            queryItems: queryItems,
            method: "PUT"
        )
    }
}
