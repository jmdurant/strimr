import Foundation

final class PlaylistRepository {
    private let network: PlexServerNetworkClient
    private let serverIdentifier: String

    struct PlaylistParams: QueryItemConvertible {
        var sectionId: Int
        var playlistType: String
        var includeCollections: Bool?

        var queryItems: [URLQueryItem] {
            [
                URLQueryItem(name: "type", value: "15"),
                URLQueryItem.make("sectionID", sectionId),
                URLQueryItem.make("playlistType", playlistType),
                URLQueryItem.makeBoolFlag("includeCollections", includeCollections),
            ].compactMap(\.self)
        }
    }

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        guard let serverIdentifier = context.serverIdentifier else {
            throw PlexAPIError.missingConnection
        }

        self.serverIdentifier = serverIdentifier
        network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }

    func getPlaylists(
        sectionId: Int,
        playlistType: String = "video",
        includeCollections: Bool = true,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        let queryItems = PlaylistParams(
            sectionId: sectionId,
            playlistType: playlistType,
            includeCollections: includeCollections,
        ).queryItems

        return try await network.request(
            path: "/playlists",
            queryItems: queryItems,
            headers: resolvedPagination.headers,
        )
    }

    func getPlaylist(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/playlists/\(ratingKey)")
    }

    func getPlaylistItems(
        ratingKey: String,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        return try await network.request(
            path: "/playlists/\(ratingKey)/items",
            headers: resolvedPagination.headers,
        )
    }

    func getAllPlaylists(
        playlistType: String,
        pagination: PlexPagination? = nil,
    ) async throws -> PlexItemMediaContainer {
        let resolvedPagination = pagination ?? PlexPagination()
        return try await network.request(
            path: "/playlists",
            queryItems: [
                URLQueryItem(name: "playlistType", value: playlistType),
            ],
            headers: resolvedPagination.headers,
        )
    }

    func createPlaylist(
        title: String,
        type: String,
        ratingKey: String,
    ) async throws -> PlexItemMediaContainer {
        let uri = metadataURI(for: ratingKey)
        return try await network.request(
            path: "/playlists",
            queryItems: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "title", value: title),
                URLQueryItem(name: "uri", value: uri),
                URLQueryItem(name: "smart", value: "0"),
            ],
            method: "POST",
        )
    }

    func addItem(toPlaylist playlistId: String, ratingKey: String) async throws {
        let uri = metadataURI(for: ratingKey)
        try await network.send(
            path: "/playlists/\(playlistId)/items",
            queryItems: [URLQueryItem(name: "uri", value: uri)],
            method: "PUT",
        )
    }

    private func metadataURI(for ratingKey: String) -> String {
        "server://\(serverIdentifier)/com.plexapp.plugins.library/library/metadata/\(ratingKey)"
    }
}
