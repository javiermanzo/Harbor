//
//  LoopbackHTTPResponder.swift
//  HarborWebSocketTests
//
//  A raw HTTP/1.1 responder on the loopback interface for handshakes that must fail: it
//  answers every request with the status the handler returns, or never answers (to exercise
//  timeouts and cancellation). `NWProtocolWebSocket` cannot produce arbitrary statuses.
//

import Foundation
import Network

/// A handshake request received by `LoopbackHTTPResponder`.
struct LoopbackHTTPRequest: Sendable {
    /// The request line, e.g. `GET /path HTTP/1.1`.
    let requestLine: String
    /// The header fields, keyed by lowercased name.
    let headers: [String: String]
}

/// What the responder does with a request.
enum LoopbackHTTPAction: Sendable {
    /// Answers with the reply and closes the connection.
    case reply(LoopbackHTTPReply)
    /// Never answers, leaving the client waiting.
    case ignore
    /// Relays the connection (the bytes already received included) to a server on the
    /// loopback interface, e.g. a `LoopbackWebSocketServer`, so the handshake continues there.
    case forward(port: UInt16)
}

/// The response the responder's handler produces.
struct LoopbackHTTPReply: Sendable {
    var statusCode: Int
    var headers: [String: String] = [:]
    var body = Data()

    fileprivate var serialized: Data {
        var head = "HTTP/1.1 \(statusCode) Status\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = "close"
        for (name, value) in allHeaders {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// HTTP server on 127.0.0.1 with a random port. Call `stop()` when done.
final class LoopbackHTTPResponder: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.tests.loopback-http-responder")
    /// Decides what to do with each request.
    private let handler: @Sendable (LoopbackHTTPRequest) -> LoopbackHTTPAction

    private let lock = NSLock()
    private var _receivedRequests: [LoopbackHTTPRequest] = []
    private var connections: [NWConnection] = []

    /// Requests received so far.
    var receivedRequests: [LoopbackHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedRequests
    }

    /// The bound port; valid after `start()`.
    private(set) var port: UInt16 = 0

    /// Creates the responder.
    /// - Parameter handler: Decides what to do with each request.
    init(handler: @escaping @Sendable (LoopbackHTTPRequest) -> LoopbackHTTPAction) throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters)
        self.handler = handler
    }

    /// Starts listening and waits until the listener is ready.
    /// - Returns: The bound port.
    @discardableResult
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        let readyPort: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedOnceFlag()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    if resumed.setIfUnset() {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error):
                    if resumed.setIfUnset() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        port = readyPort
        return readyPort
    }

    /// The `ws://` URL string of the responder, with the given path.
    func url(path: String = "/") -> String {
        "ws://127.0.0.1:\(port)\(path)"
    }

    /// Stops the listener and closes every open connection.
    func stop() {
        listener.cancel()
        lock.lock()
        let open = connections
        connections.removeAll()
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    /// Stops the responder and waits until the port is released, so a connection attempt made
    /// right after is refused instead of racing the asynchronous listener cancellation.
    func stopAndWait() async {
        stop()
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            let received = data ?? Data()
            let request = Self.parse(String(decoding: received, as: UTF8.self))
            self.lock.lock()
            self._receivedRequests.append(request)
            self.lock.unlock()
            switch self.handler(request) {
            case .ignore:
                break
            case .reply(let reply):
                connection.send(content: reply.serialized, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            case .forward(let port):
                self.forward(connection, received: received, to: port)
            }
        }
    }

    /// Relays `client` to a server on the loopback interface, both ways, starting with the
    /// bytes already read from the client.
    private func forward(_ client: NWConnection, received: Data, to port: UInt16) {
        let upstream = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        lock.lock()
        connections.append(upstream)
        lock.unlock()
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            upstream.send(content: received, completion: .contentProcessed { _ in })
            self.relay(from: client, to: upstream)
            self.relay(from: upstream, to: client)
        }
        upstream.start(queue: queue)
    }

    /// Copies bytes from one connection to the other until either side ends.
    private func relay(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { _ in })
            }
            if isComplete || error != nil {
                destination.cancel()
                source.cancel()
                return
            }
            self?.relay(from: source, to: destination)
        }
    }

    private static func parse(_ raw: String) -> LoopbackHTTPRequest {
        let head = raw.components(separatedBy: "\r\n\r\n").first ?? raw
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.isEmpty ? "" : lines.removeFirst()
        var headers: [String: String] = [:]
        for line in lines {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let name = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return LoopbackHTTPRequest(requestLine: requestLine, headers: headers)
    }
}

/// A flag that can be set once, safely across queues.
final class LockedOnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    /// Sets the flag. Returns `true` only for the first caller.
    func setIfUnset() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSet else { return false }
        isSet = true
        return true
    }
}
