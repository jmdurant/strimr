import Foundation
import os

final class PlexServerNetworkClient {
    private let session: URLSession = PlexURLSession.shared
    private var authToken: String
    private var baseURL: URL
    private var language: String
    private var clientIdentifier: String?
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    // Plex server has no client profile for watchOS — report as iOS
    private let platform: String = {
        #if os(tvOS)
            return "tvOS"
        #else
            return "iOS"
        #endif
    }()

    init(authToken: String, baseURL: URL, clientIdentifier: String? = nil, language: String = "en") {
        self.authToken = authToken
        self.baseURL = baseURL
        self.language = Locale.preferredLanguages.first ?? language
        self.clientIdentifier = clientIdentifier
    }

    func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws -> Response {
        let request = try buildRequest(path: path, queryItems: queryItems, method: method, headers: headers)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }

        if path.contains("/tune") {
            let bodyStr = String(data: data.prefix(3000), encoding: .utf8) ?? "(not utf8)"
            let logLine = "HTTP \(httpResponse.statusCode), \(data.count) bytes\n\(bodyStr)"
            AppLogger.fileLog(logLine, logger: AppLogger.network)
        }

        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            debugPrint(error)
            throw PlexAPIError.decodingFailed(error)
        }
    }

    /// Perform a request with a pre-built URL (for cases where query encoding needs manual control).
    func requestURL<Response: Decodable>(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws -> Response {
        AppLogger.network.info("\(method) \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(platform, forHTTPHeaderField: "X-Plex-Platform")
        if let appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Plex-Version")
        }
        request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(language, forHTTPHeaderField: "X-Plex-Language")
        if let clientIdentifier {
            request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
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
            debugPrint(error)
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func send(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws {
        let request = try buildRequest(path: path, queryItems: queryItems, method: method, headers: headers)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func buildRequest(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else {
            throw PlexAPIError.invalidURL
        }
        if let queryItems {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        if path.contains("/tune") {
            let msg = "\(method) \(url.absoluteString)\nclientId=\(clientIdentifier ?? "(nil)") baseURL=\(baseURL.absoluteString)"
            AppLogger.fileLog(msg, logger: AppLogger.network)
        }

        AppLogger.network.info("\(method) \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(platform, forHTTPHeaderField: "X-Plex-Platform")
        if let appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Plex-Version")
        }
        request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(language, forHTTPHeaderField: "X-Plex-Language")
        if let clientIdentifier {
            request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
