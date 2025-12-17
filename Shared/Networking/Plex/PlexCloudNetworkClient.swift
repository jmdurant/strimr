import Foundation

final class PlexCloudNetworkClient {
    private let session: URLSession = .shared
    private let baseURL = URL(string: "https://plex.tv/api/v2")!
    private var authToken: String?
    private var clientIdentifier: String

    init(authToken: String?, clientIdentifier: String) {
        self.authToken = authToken
        self.clientIdentifier = clientIdentifier
    }

    func request<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Response {
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
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        if let authToken {
            request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        }
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
            throw PlexAPIError.decodingFailed(error)
        }
    }
}
