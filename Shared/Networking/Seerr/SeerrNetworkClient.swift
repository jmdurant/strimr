import Foundation

final class SeerrNetworkClient {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    private struct EmptyBody: Encodable {}

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
    ) async throws -> Response {
        try await request(path: path, method: method, body: EmptyBody())
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        body: (some Encodable)? = nil,
    ) async throws -> Response {
        let request = try buildRequest(path: path, method: method, body: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SeerrAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw SeerrAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SeerrAPIError.decodingFailed(error)
        }
    }

    func send(
        path: String,
        method: String = "GET",
    ) async throws {
        try await send(
            path: path,
            method: method,
            body: EmptyBody(),
        )
    }

    func send(
        path: String,
        method: String = "GET",
        body: (some Encodable)? = nil,
    ) async throws {
        let request = try buildRequest(path: path, method: method, body: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SeerrAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw SeerrAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func buildRequest(
        path: String,
        method: String,
        body: (some Encodable)?,
    ) throws -> URLRequest {
        let cleanedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let apiBase = baseURL.appendingPathComponent("api/v1")
        let url = apiBase.appendingPathComponent(cleanedPath)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body, !(body is EmptyBody) {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }
}
