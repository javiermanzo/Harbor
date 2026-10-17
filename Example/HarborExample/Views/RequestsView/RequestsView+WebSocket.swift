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
        // Read the @State connection on the main actor before handing it to the task.
        let current = webSocket
        performWithLoading {
            if let current, await current.state == .open {
                await MainActor.run {
                    addResult("Already connected; send a message or close first")
                }
                return
            }
            do {
                // The handshake goes through Harbor's pipeline; the connection is an actor.
                let socket = try await EchoWebSocket().connect()
                await MainActor.run {
                    webSocket = socket
                    addResult("Connected (subprotocol: \(socket.negotiatedSubprotocol ?? "none"))")
                }

                // Read messages in a task of its own, for as long as the connection lives, so
                // the loading overlay only covers the handshake. The loop ends normally on a
                // close frame (see `state`) and throws when the connection is lost.
                Task {
                    do {
                        for try await message in socket.messages {
                            let text: String
                            switch message {
                            case .text(let value):
                                if let payload = try? message.decode(EchoPayload.self) {
                                    text = "Echoed payload #\(payload.id): \(payload.text)"
                                } else {
                                    text = "Received: \(value)"
                                }
                            case .data(let data):
                                text = "Received \(data.count) bytes"
                            }
                            await MainActor.run {
                                addResult(text)
                            }
                        }
                        let state = await socket.state
                        await MainActor.run {
                            addResult("Connection closed: \(state)")
                        }
                    } catch {
                        await MainActor.run {
                            addResult("Connection lost: \(error.localizedDescription)")
                        }
                    }
                    await MainActor.run {
                        // Only clear the socket this reader belongs to: a newer connection may
                        // already have replaced it.
                        if webSocket === socket {
                            webSocket = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    addResult("WebSocket error: \(error.localizedDescription)")
                }
            }
        }
    }

    func sendWebSocketMessage() {
        addResult("=== WebSocket - Send Message ===")
        let socket = webSocket
        performWithLoading {
            guard let socket else {
                await MainActor.run {
                    addResult("Not connected (run \"WebSocket - Connect\" first)")
                }
                return
            }
            do {
                try await socket.send("Hello from Harbor")
                try await socket.send(json: EchoPayload(id: Int.random(in: 1...999), text: "JSON through send(json:)"))
                await MainActor.run {
                    addResult("Sent a text message and a JSON payload; waiting for the echo")
                }
            } catch {
                await MainActor.run {
                    addResult("Send error: \(error.localizedDescription)")
                }
            }
        }
    }

    func closeWebSocket() {
        addResult("=== WebSocket - Close ===")
        let socket = webSocket
        performWithLoading {
            guard let socket else {
                await MainActor.run {
                    addResult("Not connected")
                }
                return
            }
            await socket.close(code: .normalClosure, reason: Data("done".utf8))
            await MainActor.run {
                addResult("Close frame sent")
            }
        }
    }
}
