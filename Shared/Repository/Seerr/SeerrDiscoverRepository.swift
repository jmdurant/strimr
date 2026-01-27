import Foundation

final class SeerrDiscoverRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func getTrending(page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = paginationQueryItems(page: page, primaryReleaseDateGte: nil)
        return try await client.request(path: "discover/trending", queryItems: queryItems)
    }

    func discoverMovies(
        page: Int,
        primaryReleaseDateGte: String? = nil,
    ) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = paginationQueryItems(page: page, primaryReleaseDateGte: primaryReleaseDateGte)
        return try await client.request(path: "discover/movies", queryItems: queryItems)
    }

    func discoverTV(
        page: Int,
        primaryReleaseDateGte: String? = nil,
    ) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = paginationQueryItems(page: page, primaryReleaseDateGte: primaryReleaseDateGte)
        return try await client.request(path: "discover/tv", queryItems: queryItems)
    }

    private func paginationQueryItems(page: Int, primaryReleaseDateGte: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "page", value: String(page))]

        if let primaryReleaseDateGte, !primaryReleaseDateGte.isEmpty {
            items.append(URLQueryItem(name: "primaryReleaseDateGte", value: primaryReleaseDateGte))
        }

        return items
    }
}
