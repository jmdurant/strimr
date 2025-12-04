import Foundation

final class MetadataRepository {
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
    
    func getMetadata(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)")
    }
    
    func getMetadataChildren(ratingKey: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/metadata/\(ratingKey)/children")
    }
}
