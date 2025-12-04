import Foundation

final class PlexMediaServerAPI {
    private let resource: PlexCloudResource
    private let language: String
    private let session: URLSession
    private var baseURL: URL?
    private var connectionCheckPerformed = false

    var isInitialized: Bool {
        baseURL != nil || connectionCheckPerformed
    }

    var isReachable: Bool {
        baseURL != nil
    }

    init(resource: PlexCloudResource, language: String, session: URLSession = .shared) {
        self.resource = resource
        self.language = language
        self.session = session
    }

    func transcodeImageURL(
        path: String,
        width: Int = 240,
        height: Int = 360,
        minSize: Int = 1,
        upscale: Int = 1
    ) -> URL? {
        guard let baseURL else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent("photo/:/transcode"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: resource.accessToken),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: String(minSize)),
            URLQueryItem(name: "upscale", value: String(upscale)),
        ]
        return components?.url
    }

    func getSections() async throws -> PlexSectionMediaContainer {
        try await request(path: "/library/sections/all")
    }

    func getSectionsItems(
        sectionId: Int,
        params: PlexSectionItemsParams = PlexSectionItemsParams(),
        pagination: PlexPagination = PlexPagination()
    ) async throws -> PlexItemMediaContainer {
        try await request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: params.toQueryItems(),
            headers: [
                "X-Plex-Container-Start": String(pagination.start),
                "X-Plex-Container-Size": String(pagination.size),
            ]
        )
    }

    func getSectionsItemsMeta(sectionId: Int) async throws -> PlexSectionMetaMediaContainer {
        try await request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: [URLQueryItem(name: "includeMeta", value: "1")],
            headers: [
                "X-Plex-Container-Start": "0",
                "X-Plex-Container-Size": "0",
            ]
        )
    }

    func getSectionsItemsMetaInfo(sectionId: Int, filter: String) async throws -> PlexDirectoryMediaContainer {
        try await request(path: "/library/sections/\(sectionId)/\(filter)")
    }

    func getContinueWatchingHub(params: PlexHubParams = PlexHubParams()) async throws -> PlexHubMediaContainer {
        try await request(path: "/hubs/continueWatching", queryItems: params.toQueryItems())
    }

    func getPromotedHub(params: PlexHubParams = PlexHubParams()) async throws -> PlexHubMediaContainer {
        var queryItems = params.toQueryItems()
        queryItems.append(contentsOf: [
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "excludeFields", value: "summary"),
            URLQueryItem(name: "excludeContinueWatching", value: "1"),
        ])
        return try await request(path: "/hubs/promoted", queryItems: queryItems)
    }

    func getSectionHubs(sectionId: Int) async throws -> PlexHubMediaContainer {
        try await request(
            path: "/hubs/sections/\(sectionId)",
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "excludeFields", value: "summary"),
            ]
        )
    }

    func getMetadata(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await request(path: "/library/metadata/\(ratingKey)")
    }
    
    func getMetadataChildren(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await request(path: "/library/metadata/\(ratingKey)/children")
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:]
    ) async throws -> Response {
        let baseURL = try await ensureConnection()

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw PlexAPIError.invalidURL
        }
        if let queryItems {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(resource.accessToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(language, forHTTPHeaderField: "X-Plex-Language")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            debugPrint(error)
            throw PlexAPIError.decodingFailed(error)
        }
    }

    private func resolveConnection() async throws -> PlexCloudResource.Connection? {
        let sortedConnections = resource.connections.sorted { lhs, rhs in
            if lhs.isRelay != rhs.isRelay {
                return rhs.isRelay // non-relay first
            }
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal // local first
            }
            return false
        }

        for connection in sortedConnections {
            if try await isConnectionReachable(connection) {
                return connection
            }
        }

        return nil
    }

    private func isConnectionReachable(_ connection: PlexCloudResource.Connection) async throws -> Bool {
        var request = URLRequest(url: connection.uri)
        request.setValue(resource.accessToken, forHTTPHeaderField: "X-Plex-Token")
        request.timeoutInterval = 3

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode < 500
        } catch {
            return false
        }
    }
}
