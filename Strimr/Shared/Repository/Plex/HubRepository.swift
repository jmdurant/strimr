import Foundation

struct PlexHubParams {
    var sectionIds: [Int] = []

    func toQueryItems() -> [URLQueryItem] {
        guard !sectionIds.isEmpty else { return [] }
        return [PlexQueryValue.intArray(sectionIds).asQueryItem(key: "sectionIds")]
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
        try await network.request(path: "/hubs/continueWatching", queryItems: params.toQueryItems())
    }

    func getPromotedHub(params: PlexHubParams = PlexHubParams()) async throws -> PlexHubMediaContainer {
        var queryItems = params.toQueryItems()
        queryItems.append(contentsOf: [
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "excludeFields", value: "summary"),
            URLQueryItem(name: "excludeContinueWatching", value: "1"),
        ])
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
