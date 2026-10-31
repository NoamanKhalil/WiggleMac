import Foundation
import Network

/// A small HTTP server that only this Mac can reach (127.0.0.1), for the Photon bridge to pass on
/// texts and get Wiggle's replies. Every request needs the token in remote.json, which is readable by
/// this user only and changes each time the server starts. Web pages are turned away.
@MainActor
final class RemoteServer {
    struct Request: Equatable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct Response {
        var status: Int
        var json: [String: Any]
    }

    var handler: ((Request) async -> Response)?
    private var listener: NWListener?
    private var token = ""

    /// Where the bridge finds the port and token.
    static var infoURL: URL {
        URL.applicationSupportDirectory.appending(path: "Wiggle/remote.json")
    }

    var isRunning: Bool { listener != nil }

    func start() throws {
        guard listener == nil else { return }
        token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = self.listener?.port?.rawValue { self.writeInfo(port: port) }
                case .failed(let error):
                    NSLog("Wiggle's texting server stopped: \(error.localizedDescription)")
                    self.stop()
                default:
                    break
                }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(at: Self.infoURL)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                var buffer = buffer
                if let data { buffer.append(data) }
                guard let self else { return connection.cancel() }
                if let request = Self.parse(buffer) {
                    Task { await self.respond(to: request, on: connection) }
                } else if isComplete || error != nil || buffer.count > 1_000_000 {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) async {
        let response: Response
        if !Self.isAllowed(request, token: token) {
            response = Response(status: 401, json: ["error": "Not allowed."])
        } else if let handler {
            response = await handler(request)
        } else {
            response = Response(status: 503, json: ["error": "Wiggle isn't ready."])
        }
        let body = (try? JSONSerialization.data(withJSONObject: response.json)) ?? Data("{}".utf8)
        let head = "HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Error")\r\n"
            + "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - HTTP

    /// The request in `data`, once its headers and body have all arrived.
    nonisolated static func parse(_ data: Data) -> Request? {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<end.lowerBound], encoding: .utf8)
        else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }

    /// The token, and not from a browser: a web page could reach 127.0.0.1, but sends an Origin header,
    /// and through DNS tricks a Host other than 127.0.0.1.
    nonisolated static func isAllowed(_ request: Request, token: String) -> Bool {
        guard !token.isEmpty, request.headers["authorization"] == "Bearer \(token)", request.headers["origin"] == nil
        else { return false }
        let host = request.headers["host"] ?? ""
        return host.hasPrefix("127.0.0.1:") || host == "127.0.0.1"
    }

    private func writeInfo(port: UInt16) {
        let url = Self.infoURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["port": Int(port), "token": token])
            try? FileManager.default.removeItem(at: url)
            guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            NSLog("Wiggle couldn't write \(url.path): \(error.localizedDescription)")
        }
    }
}
