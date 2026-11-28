//
//  WebSocketSection.swift
//  HarborExample
//
//  `HWebSocket` against a public echo server: connect, send, receive and close.
//

import SwiftUI
import HarborWebSocket
import Harbor

struct WebSocketSection: View {
    @EnvironmentObject private var runner: ExampleRunner

    /// The open connection, kept across render passes.
    @State private var webSocket: HWebSocket?

    var body: some View {
        ExampleSection(title: "WebSocket (Echo)") {
            ExampleButton(title: "WebSocket - Connect", icon: "bolt.horizontal.circle") { connectWebSocket() }
            ExampleButton(title: "WebSocket - Send Message", icon: "paperplane.circle") { sendWebSocketMessage() }
            ExampleButton(title: "WebSocket - Close", icon: "xmark.circle", isDestructive: true) { closeWebSocket() }
        }
        .onDisappear {
            // Close the demo connection with the section; its reader task then ends too.
            let socket = webSocket
            Task { await socket?.close(code: .goingAway) }
        }
    }

    // MARK: - Actions

    private func connectWebSocket() {
        runner.log("=== WebSocket - Connect ===")
        runner.run {
            if let webSocket, await webSocket.state == .open {
                runner.log("Already connected; send a message or close first")
                return
            }
            do {
                // The handshake goes through Harbor's pipeline; the connection is an actor.
                let socket = try await EchoWebSocket().connect()
                webSocket = socket
                runner.log("Connected (subprotocol: \(socket.negotiatedSubprotocol ?? "none"))")
                // Read in a task of its own so the loading overlay only covers the handshake.
                Task { await listen(to: socket) }
            } catch {
                runner.log("WebSocket error: \(error.localizedDescription)")
            }
        }
    }

    private func sendWebSocketMessage() {
        runner.log("=== WebSocket - Send Message ===")
        runner.run {
            guard let webSocket else {
                runner.log("Not connected (run \"WebSocket - Connect\" first)")
                return
            }
            do {
                try await webSocket.send("Hello from Harbor")
                try await webSocket.send(json: EchoPayload(id: Int.random(in: 1...999), text: "JSON through send(json:)"))
                runner.log("Sent a text message and a JSON payload; waiting for the echo")
            } catch {
                runner.log("Send error: \(error.localizedDescription)")
            }
        }
    }

    private func closeWebSocket() {
        runner.log("=== WebSocket - Close ===")
        runner.run {
            guard let webSocket else {
                runner.log("Not connected")
                return
            }
            await webSocket.close(code: .normalClosure, reason: Data("done".utf8))
            runner.log("Close frame sent")
        }
    }

    /// Prints every message until the connection ends: normally after a close frame (see
    /// `state`), throwing when the connection is lost without one.
    private func listen(to socket: HWebSocket) async {
        do {
            for try await message in socket.messages {
                // `decode` works for text and binary messages alike.
                if let payload = try? message.decode(EchoPayload.self) {
                    runner.log("Echoed payload #\(payload.id): \(payload.text)")
                } else {
                    switch message {
                    case .text(let value): runner.log("Received: \(value)")
                    case .data(let data): runner.log("Received \(data.count) bytes")
                    }
                }
            }
            runner.log("Connection closed: \(await socket.state)")
        } catch {
            runner.log("Connection lost: \(error.localizedDescription)")
        }
        // Only clear the socket this reader belongs to: a newer connection may have replaced it.
        if webSocket === socket {
            webSocket = nil
        }
    }
}
