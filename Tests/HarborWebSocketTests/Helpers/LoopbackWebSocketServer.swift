//
//  LoopbackWebSocketServer.swift
//  HarborWebSocketTests
//
//  A minimal WebSocket server bound to the loopback interface, built on Network.framework's
//  `NWProtocolWebSocket`. Lets tests exercise the real `URLSessionWebSocketTask` transport
//  (handshake, subprotocols, headers, messages, ping/pong, close frames) without leaving the machine.
//

import Foundation
import Network
import Security

/// A WebSocket message received or sent by `LoopbackWebSocketServer`.
enum LoopbackWebSocketFrame: Sendable, Equatable {
    case text(String)
    case data(Data)
    case ping
    case pong
    case close(code: NWProtocolWebSocket.CloseCode?)
}

/// The handshake request a client sent, as seen by the server.
struct LoopbackWebSocketHandshake: Sendable {
    /// The subprotocols offered by the client (`Sec-WebSocket-Protocol`).
    let subprotocols: [String]
    /// The request headers, keyed by lowercased name.
    let headers: [String: String]
}

/// WebSocket server on 127.0.0.1 with a random port. Call `stop()` when done.
///
/// Every accepted connection is handed to `onConnection`, which gets a `Connection` handle to
/// send frames and read the frames received so far. The handshake decision is taken by
/// `handshakeHandler` (accept with an optional subprotocol, or reject).
final class LoopbackWebSocketServer: @unchecked Sendable {

    /// A client connection accepted by the server.
    final class Connection: @unchecked Sendable {
        fileprivate let connection: NWConnection
        private let lock = NSLock()
        private var _received: [LoopbackWebSocketFrame] = []
        private var waiters: [(count: Int, continuation: CheckedContinuation<[LoopbackWebSocketFrame], Never>)] = []

        fileprivate init(connection: NWConnection) {
            self.connection = connection
        }

        /// Frames received so far.
        var received: [LoopbackWebSocketFrame] {
            lock.lock()
            defer { lock.unlock() }
            return _received
        }

        /// Waits until at least `count` frames were received.
        func waitForFrames(count: Int) async -> [LoopbackWebSocketFrame] {
            await withCheckedContinuation { continuation in
                lock.lock()
                if _received.count >= count {
                    let frames = _received
                    lock.unlock()
                    continuation.resume(returning: frames)
                    return
                }
                waiters.append((count, continuation))
                lock.unlock()
            }
        }

        fileprivate func record(_ frame: LoopbackWebSocketFrame) {
            lock.lock()
            _received.append(frame)
            let ready = waiters.filter { $0.count <= _received.count }
            waiters.removeAll { $0.count <= _received.count }
            let frames = _received
            lock.unlock()
            ready.forEach { $0.continuation.resume(returning: frames) }
        }

        /// Sends a text message.
        func send(text: String) {
            send(Data(text.utf8), opcode: .text)
        }

        /// Sends a binary message.
        func send(data: Data) {
            send(data, opcode: .binary)
        }

        /// Sends a ping frame.
        func ping() {
            send(Data(), opcode: .ping)
        }

        /// Sends a close frame with the given code and reason, then closes the connection.
        func close(code: NWProtocolWebSocket.CloseCode = .protocolCode(.normalClosure), reason: Data? = nil) {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
            metadata.closeCode = code
            let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
            connection.send(content: reason, contentContext: context, isComplete: true, completion: .contentProcessed { [connection] _ in
                connection.cancel()
            })
        }

        /// Drops the TCP connection without a close frame.
        func drop() {
            connection.forceCancel()
        }

        private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
            let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
            let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
            connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.tests.loopback-websocket-server")
    private let lock = NSLock()
    private var _connections: [Connection] = []
    private var _handshakes: [LoopbackWebSocketHandshake] = []
    private let onConnection: @Sendable (Connection) -> Void

    /// The bound port; valid after `start()`.
    private(set) var port: UInt16 = 0

    /// Connections accepted so far.
    var connections: [Connection] {
        lock.lock()
        defer { lock.unlock() }
        return _connections
    }

    /// Handshake requests seen so far (accepted or rejected).
    var handshakes: [LoopbackWebSocketHandshake] {
        lock.lock()
        defer { lock.unlock() }
        return _handshakes
    }

    /// Creates the server.
    /// - Parameters:
    ///   - identity: When given, the server speaks TLS presenting this identity (`wss://`).
    ///   - autoReplyPing: Whether the framework answers pings itself. Default `true`.
    ///   - handshakeHandler: Decides the handshake response. Default: accept with the first offered subprotocol.
    ///   - onConnection: Called for every accepted connection.
    init(identity: SecIdentity? = nil,
         autoReplyPing: Bool = true,
         handshakeHandler: @escaping @Sendable (LoopbackWebSocketHandshake) -> NWProtocolWebSocket.Response = { handshake in
             NWProtocolWebSocket.Response(status: .accept, subprotocol: handshake.subprotocols.first)
         },
         onConnection: @escaping @Sendable (Connection) -> Void = { _ in }) throws {
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

        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = autoReplyPing
        let recorder = HandshakeRecorder()
        webSocketOptions.setClientRequestHandler(queue) { subprotocols, additionalHeaders in
            var headers: [String: String] = [:]
            for header in additionalHeaders {
                headers[header.name.lowercased()] = header.value
            }
            let handshake = LoopbackWebSocketHandshake(subprotocols: subprotocols, headers: headers)
            recorder.record?(handshake)
            return handshakeHandler(handshake)
        }
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        self.listener = try NWListener(using: parameters)
        self.onConnection = onConnection
        recorder.record = { [weak self] handshake in
            guard let self else { return }
            self.lock.lock()
            self._handshakes.append(handshake)
            self.lock.unlock()
        }
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

    /// The `ws://` (or `wss://`) URL string of the server, with the given path.
    func url(path: String = "/", secure: Bool = false) -> String {
        "\(secure ? "wss" : "ws")://127.0.0.1:\(port)\(path)"
    }

    /// Stops the listener and closes every open connection.
    func stop() {
        listener.cancel()
        lock.lock()
        let open = _connections
        _connections.removeAll()
        lock.unlock()
        open.forEach { $0.connection.cancel() }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = Connection(connection: nwConnection)
        lock.lock()
        _connections.append(connection)
        lock.unlock()
        nwConnection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .ready = state, let connection {
                self?.onConnection(connection)
            }
        }
        nwConnection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: Connection) {
        connection.connection.receiveMessage { [weak self, weak connection] data, context, _, error in
            guard let self, let connection else { return }
            if let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                switch metadata.opcode {
                case .text:
                    connection.record(.text(String(decoding: data ?? Data(), as: UTF8.self)))
                case .binary:
                    connection.record(.data(data ?? Data()))
                case .ping:
                    connection.record(.ping)
                case .pong:
                    connection.record(.pong)
                case .close:
                    connection.record(.close(code: metadata.closeCode))
                    return
                case .cont:
                    break
                @unknown default:
                    break
                }
            }
            if error != nil {
                return
            }
            self.receive(on: connection)
        }
    }
}

/// Boxes the handshake recording closure so the request handler, which is installed before
/// the server is fully initialized, can reach the server afterwards.
private final class HandshakeRecorder: @unchecked Sendable {
    var record: (@Sendable (LoopbackWebSocketHandshake) -> Void)?
}
