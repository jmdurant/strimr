import Foundation

final class SeerrMediaRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func getMovie(id: Int) async throws -> SeerrMedia {
        try await client.request(path: "movie/\(id)")
    }

    func getTV(id: Int) async throws -> SeerrMedia {
        try await client.request(path: "tv/\(id)")
    }

    func getTVSeason(id: Int, seasonNumber: Int) async throws -> SeerrSeason {
        try await client.request(path: "tv/\(id)/season/\(seasonNumber)")
    }
}
