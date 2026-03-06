import Foundation

final class AuthRepository {
    private let network: PlexCloudNetworkClient
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) {
        self.context = context
        network = PlexCloudNetworkClient(authToken: context.authTokenCloud, clientIdentifier: context.clientIdentifier)
    }

    func requestPin() async throws -> PlexCloudPin {
        try await network.request(
            path: "/pins",
            method: "POST",
            queryItems: [URLQueryItem(name: "strong", value: "true")],
        )
    }

    func pollToken(pinId: Int) async throws -> PlexCloudPin {
        try await network.request(path: "/pins/\(pinId)", method: "GET")
    }

    func signIn(login: String, password: String) async throws -> PlexCloudUser {
        guard let context else { throw PlexAPIError.invalidURL }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove("+")
        allowed.remove("&")
        allowed.remove("=")
        let encodedLogin = login.addingPercentEncoding(withAllowedCharacters: allowed) ?? login
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: allowed) ?? password

        var request = URLRequest(url: URL(string: "https://plex.tv/users/sign_in.json")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(context.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.httpBody = "user[login]=\(encodedLogin)&user[password]=\(encodedPassword)".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }
        let wrapper = try JSONDecoder().decode(PlexSignInResponse.self, from: data)
        return wrapper.user
    }
}

private struct PlexSignInResponse: Decodable {
    let user: PlexCloudUser
}
