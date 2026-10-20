//
//  RequestsView+WebSocket.swift
//  HarborExample
//
//  WebSocket connection
//

import SwiftUI
import HarborJRPC
import HarborWebSocket
import Harbor
import LogBird

// MARK: - WebSocket connection
extension RequestsView {
    func connectWebSocket() {
        addResult("=== WebSocket - Connect ===")
        performWithLoading {
            if let webSocket, await webSocket.state == .open {
                addResult("Already connected; send a message or close first")
                return
            }
            do {
                // The handshake goes through Harbor's pipeline; the connection is an actor.
                let socket = try await EchoWebSocket().connect()
                webSocket = socket
                addResult("Connected (subprotocol: \(socket.negotiatedSubprotocol ?? "none"))")
                // Read in a task of its own so the loading overlay only covers the handshake.
                Task { await listen(to: socket) }
            } catch {
                addResult("WebSocket error: \(error.localizedDescription)")
            }
        }
    }

    func sendWebSocketMessage() {
        addResult("=== WebSocket - Send Message ===")
        performWithLoading {
            guard let webSocket else {
                addResult("Not connected (run \"WebSocket - Connect\" first)")
                return
            }
            do {
                try await webSocket.send("Hello from Harbor")
                try await webSocket.send(json: EchoPayload(id: Int.random(in: 1...999), text: "JSON through send(json:)"))
                addResult("Sent a text message and a JSON payload; waiting for the echo")
            } catch {
                addResult("Send error: \(error.localizedDescription)")
            }
        }
    }

    func closeWebSocket() {
        addResult("=== WebSocket - Close ===")
        performWithLoading {
            guard let webSocket else {
                addResult("Not connected")
                return
            }
            await webSocket.close(code: .normalClosure, reason: Data("done".utf8))
            addResult("Close frame sent")
        }
    }

    /// Prints every message until the connection ends: normally after a close frame (see
    /// `state`), throwing when the connection is lost without one.
    private func listen(to socket: HWebSocket) async {
        do {
            for try await message in socket.messages {
                // `decode` works for text and binary messages alike.
                if let payload = try? message.decode(EchoPayload.self) {
                    addResult("Echoed payload #\(payload.id): \(payload.text)")
                } else {
                    switch message {
                    case .text(let value): addResult("Received: \(value)")
                    case .data(let data): addResult("Received \(data.count) bytes")
                    }
                }
            }
            addResult("Connection closed: \(await socket.state)")
        } catch {
            addResult("Connection lost: \(error.localizedDescription)")
        }
        // Only clear the socket this reader belongs to: a newer connection may have replaced it.
        if webSocket === socket {
            webSocket = nil
        }
    }
}
