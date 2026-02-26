import Foundation

final class TranscodeRepository {
    private let baseURL: URL
    private let authToken: String
    private let clientIdentifier: String
    private let network: PlexServerNetworkClient
    // Plex server has no client profile for watchOS — report as iOS
    // so the server can select appropriate transcode settings
    private let platform: String = {
        #if os(tvOS)
            return "tvOS"
        #else
            return "iOS"
        #endif
    }()
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

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
        maxVideoBitrate: Int = 720,
        videoResolution: String = "480x320"
    ) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/video/:/transcode/universal/start.m3u8"
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "maxVideoBitrate", value: String(maxVideoBitrate)),
            URLQueryItem(name: "videoQuality", value: "75"),
            URLQueryItem(name: "videoResolution", value: videoResolution),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(partIndex)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier),
            URLQueryItem(name: "location", value: "lan"),
            URLQueryItem(name: "X-Plex-Product", value: "Strimr"),
            URLQueryItem(name: "X-Plex-Platform", value: platform),
            URLQueryItem(name: "X-Plex-Version", value: appVersion),
            URLQueryItem(
                name: "X-Plex-Client-Profile-Extra",
                value: "append-transcode-target-codec(type=videoProfile&context=streaming&protocol=hls&videoCodec=\(videoCodec)&audioCodec=\(audioCodec))"
            ),
        ]
        return components?.url
    }

    func transcodeDownloadURL(
        path: String,
        session: String,
        mediaIndex: Int = 0,
        partIndex: Int = 0,
        videoCodec: String = "h264",
        audioCodec: String = "aac",
        maxVideoBitrate: Int = 720,
        videoResolution: String = "480x320"
    ) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/video/:/transcode/universal/start"
        components?.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "session", value: session),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "maxVideoBitrate", value: String(maxVideoBitrate)),
            URLQueryItem(name: "videoQuality", value: "75"),
            URLQueryItem(name: "videoResolution", value: videoResolution),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(partIndex)),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier),
            URLQueryItem(name: "location", value: "lan"),
            URLQueryItem(name: "X-Plex-Product", value: "Strimr"),
            URLQueryItem(name: "X-Plex-Platform", value: platform),
            URLQueryItem(name: "X-Plex-Version", value: appVersion),
            URLQueryItem(
                name: "X-Plex-Client-Profile-Extra",
                value: "append-transcode-target-codec(type=videoProfile&context=streaming&protocol=http&videoCodec=\(videoCodec)&audioCodec=\(audioCodec))"
            ),
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
