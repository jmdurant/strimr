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

    /// Fetch channels for a DVR lineup.
    func getChannels(lineup: String) async throws -> PlexChannelListResponse {
        // The lineup value from the server may be partially percent-encoded.
        // First decode it fully, then re-encode for use in a query string.
        let decoded = lineup.removingPercentEncoding ?? lineup
        let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? decoded
        var components = URLComponents(url: baseURL.appendingPathComponent("/livetv/epg/channels"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = "lineup=\(encoded)"
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }
        return try await network.requestURL(url: url)
    }

    /// Tune to a channel on a given DVR.
    func tuneChannel(dvrKey: String, channelIdentifier: String) async throws -> PlexTuneResponse {
        try await network.request(
            path: "/livetv/dvrs/\(dvrKey)/channels/\(channelIdentifier)/tune",
            method: "POST"
        )
    }

    /// Discover the EPG provider key (e.g. "tv.plex.providers.epg.onconnect:16").
    func getEPGProviderKey() async throws -> String? {
        let response: PlexEPGProviderResponse = try await network.request(
            path: "/tv.plex.providers.epg.cloud"
        )
        // The second directory entry contains the grid key
        guard let directories = response.mediaContainer.directory,
              directories.count >= 2,
              let key = directories[1].title
        else {
            return nil
        }
        return key
    }

    /// Fetch programs airing right now from the EPG grid.
    func getNowPlaying(epgKey: String) async throws -> PlexEPGGridResponse {
        let now = String(Int(Date().timeIntervalSince1970))
        var components = URLComponents(url: baseURL.appendingPathComponent("/\(epgKey)/grid"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "type", value: "4"),
            URLQueryItem(name: "beginsAt%3C", value: now),
            URLQueryItem(name: "endsAt%3E", value: now),
        ]
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }
        return try await network.requestURL(url: url)
    }

    /// Fetch programs within a time window from the EPG grid.
    func getEPGGrid(epgKey: String, from: Int, to: Int) async throws -> PlexEPGGridResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/\(epgKey)/grid"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "type", value: "4"),
            URLQueryItem(name: "beginsAt%3C", value: String(to)),
            URLQueryItem(name: "endsAt%3E", value: String(from)),
        ]
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }
        return try await network.requestURL(url: url)
    }

    /// Fetch a pre-built recording template for a program.
    func getRecordingTemplate(key: String) async throws -> PlexSubscriptionTemplateResponse {
        try await network.request(
            path: "/media/subscriptions/template",
            queryItems: [URLQueryItem(name: "key", value: key)]
        )
    }

    /// Schedule a single recording using template parameters.
    func scheduleRecording(parameters: String) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("/media/subscriptions"), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = parameters + "&prefs[oneShot]=true"
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")

        NSLog("[PlexNetwork] POST %@", url.absoluteString)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
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
