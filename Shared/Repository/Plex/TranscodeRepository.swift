import Foundation

final class TranscodeRepository {
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

    func transcodeURL(
        path: String,
        session: String,
        offset: Int = 0,
        mediaIndex: Int = 0,
        partIndex: Int = 0,
        videoCodec: String = "h264",
        audioCodec: String = "aac",
        maxVideoBitrate: Int = 2000,
        videoResolution: String = "480x360"
    ) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/video/:/transcode/universal/start.m3u8"
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "videoCodec", value: videoCodec),
            URLQueryItem(name: "audioCodec", value: audioCodec),
            URLQueryItem(name: "maxVideoBitrate", value: String(maxVideoBitrate)),
            URLQueryItem(name: "videoResolution", value: videoResolution),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(partIndex)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "copyts", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier),
        ]
        return components?.url
    }

    func stopSession(id: String) async throws {
        try await network.send(
            path: "/video/:/transcode/universal/stop",
            queryItems: [URLQueryItem(name: "session", value: id)]
        )
    }
}
