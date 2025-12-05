import Foundation

struct PlexHubParams: QueryItemConvertible {
    var sectionIds: [Int]?
    var count: Int?
    var excludeFields: [String]?
    var excludeContinueWatching: Bool?

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem.makeArray("sectionIds", sectionIds),
            URLQueryItem.make("count", count),
            URLQueryItem.makeArray("excludeFields", excludeFields),
            URLQueryItem.makeBoolFlag("excludeContinueWatching", excludeContinueWatching),
        ].compactMap { $0 }
    }
}

final class HubRepository {
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
    
    func getContinueWatchingHub(params: PlexHubParams = PlexHubParams()) async throws -> PlexHubMediaContainer {
        try await network.request(path: "/hubs/continueWatching", queryItems: params.queryItems)
    }

    func getPromotedHub(params: PlexHubParams = PlexHubParams()) async throws -> PlexHubMediaContainer {
        var queryItems = params.queryItems
        if params.count == nil {
            queryItems.append(URLQueryItem(name: "count", value: "20"))
        }
        if params.excludeFields == nil {
            queryItems.append(URLQueryItem(name: "excludeFields", value: "summary"))
        }
        if params.excludeContinueWatching == nil {
            queryItems.append(URLQueryItem(name: "excludeContinueWatching", value: "1"))
        }
        return try await network.request(path: "/hubs/promoted", queryItems: queryItems)
    }

    func getSectionHubs(sectionId: Int) async throws -> PlexHubMediaContainer {
        try await network.request(
            path: "/hubs/sections/\(sectionId)",
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "excludeFields", value: "summary"),
            ]
        )
    }
}
