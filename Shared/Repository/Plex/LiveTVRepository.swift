import Foundation

final class LiveTVRepository {
    private let baseURL: URL
    private let authToken: String
    private let clientIdentifier: String
    private let network: PlexServerNetworkClient

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        baseURL = baseURLServer
        self.authToken = authToken
        clientIdentifier = context.clientIdentifier
        network = PlexServerNetworkClient(
            authToken: authToken,
            baseURL: baseURLServer,
            clientIdentifier: context.clientIdentifier
        )
    }

    func getDVRs() async throws -> PlexDVRResponse {
        try await network.request(path: "/livetv/dvrs")
    }

    func getChannels(dvrKey: String) async throws -> PlexChannelListResponse {
        try await network.request(path: "/livetv/dvrs/\(dvrKey)/channels")
    }

    func tuneChannel(dvrKey: String, channelKey: String) async throws -> PlexTuneResponse {
        try await network.request(
            path: "/livetv/dvrs/\(dvrKey)/channels/\(channelKey)/tune",
            method: "POST"
        )
    }

    func streamURL(partKey: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = partKey
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "X-Plex-Token", value: authToken))
        components?.queryItems = queryItems
        return components?.url
    }
}
