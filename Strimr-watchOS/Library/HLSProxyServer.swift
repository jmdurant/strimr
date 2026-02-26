import Foundation
import Network

final class HLSProxyServer: @unchecked Sendable {
    static let shared = HLSProxyServer()

    private var listener: NWListener?
    private var serverBaseURL: URL?
    private var activeConnections: [NWConnection] = []
    private let queue = DispatchQueue(label: "com.strimr.hlsproxy")
    private(set) var port: UInt16 = 0

    var isRunning: Bool { listener != nil }

    func start(baseURL: URL) async throws {
        if isRunning { stop() }
        serverBaseURL = baseURL

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let nwListener = try NWListener(using: parameters, on: .any)

        nwListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let assignedPort = nwListener.port?.rawValue {
                    self?.port = assignedPort
                    writeDebug("[HLSProxy] listening on localhost:\(assignedPort)")
                }
            case .failed(let error):
                writeDebug("[HLSProxy] listener failed: \(error)")
                self?.stop()
            default:
                break
            }
        }

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener = nwListener
        nwListener.start(queue: queue)

        // Wait briefly for the port to be assigned
        for _ in 0..<20 {
            if port != 0 { break }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        guard port != 0 else {
            stop()
            throw URLError(.cannotConnectToHost)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.activeConnections {
                connection.cancel()
            }
            self.activeConnections.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.port = 0
            writeDebug("[HLSProxy] stopped")
        }
    }

    func proxyURL(for originalURL: URL) -> URL? {
        guard port != 0 else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = originalURL.path
        components.query = originalURL.query
        return components.url
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        activeConnections.append(connection)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state, let connection {
                self?.removeConnection(connection)
            }
        }

        connection.start(queue: queue)
        receiveRequest(from: connection)
    }

    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                self?.removeConnection(connection)
                return
            }

            guard let request = self.parseHTTPRequest(data) else {
                self.sendErrorResponse(status: 400, message: "Bad Request", to: connection)
                return
            }

            writeDebug("[HLSProxy] \(request.method) \(request.path)")
            self.forwardRequest(request, to: connection)
        }
    }

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
    }

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let requestString = String(data: data, encoding: .utf8) else { return nil }
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return HTTPRequest(method: method, path: path, headers: headers)
    }

    // MARK: - Forwarding

    private func forwardRequest(_ request: HTTPRequest, to connection: NWConnection) {
        guard let serverBaseURL else {
            sendErrorResponse(status: 502, message: "No server configured", to: connection)
            return
        }

        Task {
            do {
                // Reconstruct the full Plex server URL by string concatenation
                // to preserve special characters like colons in /video/:/transcode/...
                let base = serverBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let path = request.path.hasPrefix("/") ? request.path : "/\(request.path)"
                let urlString = base + path

                guard let forwardURL = URL(string: urlString) else {
                    self.sendErrorResponse(status: 400, message: "Invalid URL", to: connection)
                    return
                }

                writeDebug("[HLSProxy] forwarding to: \(forwardURL.absoluteString.prefix(200))...")

                var urlRequest = URLRequest(url: forwardURL)
                urlRequest.httpMethod = request.method
                // Forward X-Plex headers from the original request
                for (key, value) in request.headers where key.hasPrefix("X-Plex") {
                    urlRequest.setValue(value, forHTTPHeaderField: key)
                }

                let (data, response) = try await PlexURLSession.shared.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.sendErrorResponse(status: 502, message: "Bad Gateway", to: connection)
                    return
                }

                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                writeDebug("[HLSProxy] response status=\(httpResponse.statusCode), contentType=\(contentType), size=\(data.count)")
                let isM3U8 = contentType.contains("mpegurl") || request.path.contains(".m3u8")

                let responseData: Data
                if isM3U8, let m3u8String = String(data: data, encoding: .utf8) {
                    writeDebug("[HLSProxy] m3u8 content: \(m3u8String)")
                    let rewritten = self.rewriteM3U8(m3u8String)
                    writeDebug("[HLSProxy] rewrote m3u8 (\(data.count) -> \(rewritten.count) bytes)")
                    responseData = rewritten.data(using: .utf8) ?? data
                } else {
                    responseData = data
                }

                self.sendResponse(
                    status: httpResponse.statusCode,
                    contentType: contentType,
                    body: responseData,
                    to: connection
                )
            } catch {
                writeDebug("[HLSProxy] forward error: \(error.localizedDescription)")
                self.sendErrorResponse(status: 502, message: "Forward failed: \(error.localizedDescription)", to: connection)
            }
        }
    }

    // MARK: - M3U8 Rewriting

    private func rewriteM3U8(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Rewrite absolute HTTPS URLs to go through proxy
            if !trimmed.hasPrefix("#") && !trimmed.isEmpty && trimmed.hasPrefix("http") {
                if let url = URL(string: trimmed), let proxied = proxyURL(for: url) {
                    result.append(proxied.absoluteString)
                    continue
                }
            }

            // Also check URI= attributes in EXT tags (e.g., EXT-X-MAP, EXT-X-MEDIA)
            if trimmed.hasPrefix("#") && trimmed.contains("URI=\"http") {
                let rewritten = rewriteURIAttributes(in: line)
                result.append(rewritten)
                continue
            }

            result.append(line)
        }

        return result.joined(separator: "\n")
    }

    private func rewriteURIAttributes(in line: String) -> String {
        var result = line
        let pattern = "URI=\"(https?://[^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
        let nsLine = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

        for match in matches.reversed() {
            guard match.numberOfRanges >= 2 else { continue }
            let urlRange = match.range(at: 1)
            let urlString = nsLine.substring(with: urlRange)
            if let url = URL(string: urlString), let proxied = proxyURL(for: url) {
                let fullRange = match.range(at: 0)
                result = (result as NSString).replacingCharacters(in: fullRange, with: "URI=\"\(proxied.absoluteString)\"")
            }
        }

        return result
    }

    // MARK: - HTTP Response Helpers

    private func sendResponse(status: Int, contentType: String, body: Data, to connection: NWConnection) {
        let statusText = HTTPURLResponse.localizedString(forStatusCode: status)
        var header = "HTTP/1.1 \(status) \(statusText)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        guard let headerData = header.data(using: .utf8) else {
            connection.cancel()
            removeConnection(connection)
            return
        }

        var fullResponse = headerData
        fullResponse.append(body)

        connection.send(content: fullResponse, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            self?.removeConnection(connection)
        })
    }

    private func sendErrorResponse(status: Int, message: String, to connection: NWConnection) {
        let body = message.data(using: .utf8) ?? Data()
        sendResponse(status: status, contentType: "text/plain", body: body, to: connection)
    }

    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
    }
}
