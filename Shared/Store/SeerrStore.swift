import Foundation
import Observation

@MainActor
@Observable
final class SeerrStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let baseURLKey = "strimr.seerr.baseURL"

    private(set) var baseURLString: String?
    private(set) var user: SeerrUser?
    private(set) var isHydrating = false
    private(set) var isValidating = false
    private(set) var isAuthenticating = false

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        baseURLString = userDefaults.string(forKey: baseURLKey)
        Task { await hydrate() }
    }

    var isLoggedIn: Bool {
        user != nil
    }

    func validateAndSaveBaseURL(_ urlString: String) async throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            throw SeerrAPIError.invalidURL
        }

        isValidating = true
        defer { isValidating = false }

        let repository = SeerrAuthRepository(baseURL: url)
        try await repository.checkStatus()

        baseURLString = url.absoluteString
        defaults.set(baseURLString, forKey: baseURLKey)
    }

    func signInWithPlex(authToken: String) async throws {
        guard let baseURL else { throw SeerrAPIError.invalidURL }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let repository = SeerrAuthRepository(baseURL: baseURL)
        try await repository.signInWithPlex(authToken: authToken)
        user = try await repository.fetchCurrentUser()
    }

    func signInWithLocal(email: String, password: String) async throws {
        guard let baseURL else { throw SeerrAPIError.invalidURL }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let repository = SeerrAuthRepository(baseURL: baseURL)
        try await repository.signInWithLocal(email: email, password: password)
        user = try await repository.fetchCurrentUser()
    }

    func signOut() {
        user = nil
        clearCookies()
    }

    func hydrate() async {
        guard let baseURL else { return }

        isHydrating = true
        defer { isHydrating = false }

        let repository = SeerrAuthRepository(baseURL: baseURL)
        do {
            user = try await repository.fetchCurrentUser()
        } catch {
            user = nil
        }
    }

    private var baseURL: URL? {
        guard let baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func clearCookies() {
        guard let baseURL else { return }
        let cookieStorage = HTTPCookieStorage.shared
        cookieStorage.cookies(for: baseURL)?.forEach { cookieStorage.deleteCookie($0) }
    }
}
