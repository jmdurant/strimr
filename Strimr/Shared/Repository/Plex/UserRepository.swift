import Foundation

final class UserRepository {
    private let network: PlexCloudNetworkClient
    private weak var context: PlexAPIContext?
    
    init(context: PlexAPIContext) {
        self.context = context
        self.network = PlexCloudNetworkClient(authToken: context.authToken, clientIdentifier: context.clientIdentifier)
    }
    
    func getUser() async throws -> PlexCloudUser {
        try await network.request(path: "/user", method: "GET")
    }
}
