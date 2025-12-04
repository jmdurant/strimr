import Foundation

struct PlexSectionItemsParams {
    var sort: String?
    var limit: Int?
    var additional: [String: PlexQueryValue] = [:]

    func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let sort {
            items.append(URLQueryItem(name: "sort", value: sort))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        items.append(contentsOf: additional.map { $0.value.asQueryItem(key: $0.key) })
        return items
    }
}

final class SectionRepository {
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
    
    func getSections() async throws -> PlexSectionMediaContainer {
        try await network.request(path: "/library/sections/all")
    }

    func getSectionsItems(
        sectionId: Int,
        params: PlexSectionItemsParams = PlexSectionItemsParams(),
        pagination: PlexPagination = PlexPagination()
    ) async throws -> PlexItemMediaContainer {
        try await network.request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: params.toQueryItems(),
            headers: [
                "X-Plex-Container-Start": String(pagination.start),
                "X-Plex-Container-Size": String(pagination.size),
            ]
        )
    }

    func getSectionsItemsMeta(sectionId: Int) async throws -> PlexSectionMetaMediaContainer {
        try await network.request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: [URLQueryItem(name: "includeMeta", value: "1")],
            headers: [
                "X-Plex-Container-Start": "0",
                "X-Plex-Container-Size": "0",
            ]
        )
    }

    func getSectionsItemsMetaInfo(sectionId: Int, filter: String) async throws -> PlexDirectoryMediaContainer {
        try await network.request(path: "/library/sections/\(sectionId)/\(filter)")
    }
}
