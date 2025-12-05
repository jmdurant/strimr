import Foundation

struct PlexSectionItemsParams: QueryItemConvertible {
    var sort: String?
    var limit: Int?
    var includeMeta: Bool?

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem.make("sort", sort),
            URLQueryItem.make("limit", limit),
            URLQueryItem.makeBoolFlag("includeMeta", includeMeta),
        ].compactMap { $0 }
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
            queryItems: params.queryItems,
            headers: pagination.headers
        )
    }

    func getSectionsItemsMeta(sectionId: Int) async throws -> PlexSectionMetaMediaContainer {
        try await network.request(
            path: "/library/sections/\(sectionId)/all",
            queryItems: PlexSectionItemsParams(includeMeta: true).queryItems,
            headers: PlexPagination(start: 0, size: 0).headers
        )
    }

    func getSectionsItemsMetaInfo(sectionId: Int, filter: String) async throws -> PlexDirectoryMediaContainer {
        try await network.request(path: "/library/sections/\(sectionId)/\(filter)")
    }
}
