import Foundation

/// Shared URLSession that trusts .plex.direct TLS certificates.
/// Use this for all requests to Plex servers (not plex.tv cloud API).
enum PlexURLSession {
    static let shared: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: TrustDelegate(), delegateQueue: nil)
    }()
}

private final class TrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust,
           challenge.protectionSpace.host.hasSuffix(".plex.direct")
        {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
