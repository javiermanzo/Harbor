//
//  LoopbackHTTPServer.swift
//  HarborTests
//
//  A minimal HTTP/1.1 server bound to the loopback interface, optionally speaking TLS with a
//  given identity. Lets tests exercise real URLSession behavior (TLS handshakes, redirects)
//  without leaving the machine.
//

import Foundation
import Network
import Security

/// A raw HTTP request received by `LoopbackHTTPServer`.
struct LoopbackHTTPRequest: Sendable {
    /// The request line, e.g. `GET /path HTTP/1.1`.
    let requestLine: String
    /// The header fields, keyed by lowercased name.
    let headers: [String: String]
    /// The request body, read up to `Content-Length` bytes.
    var body = Data()

    /// The request path from the request line.
    var path: String {
        let parts = requestLine.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : ""
    }
}

/// A response produced by `LoopbackHTTPServer`'s handler.
struct LoopbackHTTPResponse: Sendable {
    var statusCode: Int
    var headers: [String: String] = [:]
    var body: Data = Data()

    /// Serializes the response; the connection is closed after it is sent.
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

/// HTTP(S) server on 127.0.0.1 with a random port. Call `stop()` when done.
final class LoopbackHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.tests.loopback-server")
    private let handler: @Sendable (LoopbackHTTPRequest) -> LoopbackHTTPResponse

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

    /// Creates the server.
    /// - Parameters:
    ///   - identity: When given, the server speaks TLS presenting this identity.
    ///   - handler: Produces the response for each request.
    init(identity: SecIdentity? = nil, handler: @escaping @Sendable (LoopbackHTTPRequest) -> LoopbackHTTPResponse) throws {
        let parameters: NWParameters
        if let identity, let secIdentity = sec_identity_create(identity) {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secIdentity)
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = .tcp
        }
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        self.listener = try NWListener(using: parameters)
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
            let resumed = LockedFlag()
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

    /// Stops the listener and closes every open connection.
    func stop() {
        listener.cancel()
        lock.lock()
        let open = connections
        connections.removeAll()
        lock.unlock()
        open.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                var request = Self.parse(head)
                // Wait for the whole body announced by Content-Length before answering.
                let contentLength = request.headers["content-length"].flatMap { Int($0) } ?? 0
                let received = buffer.count - headerEnd.upperBound
                if received < contentLength, !isComplete, error == nil {
                    self.receive(on: connection, buffer: buffer)
                    return
                }
                request.body = Data(buffer[headerEnd.upperBound...].prefix(contentLength))
                self.lock.lock()
                self._receivedRequests.append(request)
                self.lock.unlock()
                let response = self.handler(request)
                connection.send(content: response.serialized, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: buffer)
        }
    }

    private static func parse(_ head: String) -> LoopbackHTTPRequest {
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
private final class LockedFlag: @unchecked Sendable {
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
