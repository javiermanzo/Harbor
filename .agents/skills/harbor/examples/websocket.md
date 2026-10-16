# Harbor WebSocket Examples

`HarborWebSocket` opens WebSocket connections (RFC 6455) through Harbor's pipeline: the handshake gets the connectivity check, the auth provider (with the `401` refresh flow), default headers, the retry policy, SSL pinning, mTLS, the custom session and opt-in logging. The open connection is an actor that streams messages and sends yours.

```swift
import HarborWebSocket
```

## The protocol

```swift
struct ChatSocket: HWebSocketRequestProtocol {
    let url = "wss://chat.example.com/rooms/{room}"   // ws, wss, http or https (http(s) is rewritten)
    let pathParameters: [String: String]?
    let needsAuth = true
    let subprotocols = ["chat.v2", "chat.v1"]          // Sec-WebSocket-Protocol, in order of preference
    let pingInterval: TimeInterval? = 30               // keep-alive ping; pong missing → connection closed

    init(room: String) {
        pathParameters = ["room": room]
    }
}
```

| Requirement | Default |
|---|---|
| `url: String` | required |
| `pathParameters`, `queryParameters`, `headerParameters` | `nil` |
| `subprotocols: [String]` | `[]` |
| `needsAuth: Bool` | `false` |
| `retryPolicy: HRetryPolicy?` | `nil` (handshake only; treated as idempotent) |
| `timeoutInterval: TimeInterval?` | `nil`: Harbor's default (handshake only) |
| `pingInterval: TimeInterval?` | `nil`: `HarborWebSocket.setDefaultPingInterval(_:)`, which defaults to no pings |
| `maximumMessageSize: Int?` | `nil`: system default (1 MiB) |

## Connecting, reading, sending, closing

```swift
struct ChatEvent: Codable, Sendable {
    let user: String
    let text: String
}

struct JoinRoom: Encodable, Sendable {
    let room: String
}

func chat() async {
    do {
        // connect() throws an HWebSocketError when the handshake fails.
        let socket = try await ChatSocket(room: "swift").connect()
        print(socket.negotiatedSubprotocol ?? "no subprotocol")

        try await socket.send(json: JoinRoom(room: "swift"))   // JSON as a text message
        try await socket.send("hello")                           // text frame
        try await socket.send(Data([0x01, 0x02]))                // binary frame

        do {
            // Iterate from one place. The loop ends when the connection closes.
            for try await message in socket.messages {
                switch message {
                case .text(let text):
                    let event = try message.decode(ChatEvent.self)   // JSON helper, also for .data
                    print(event.user, event.text, text.count)
                case .data(let data):
                    print(data.count)
                }
            }

            // Closed by a close frame: the code and reason are in `state`.
            if case .closed(let code, let reason) = await socket.state {
                print(code, reason.map { String(decoding: $0, as: UTF8.self) } ?? "")
            }
        } catch {
            // The connection was lost, or `decode` threw: leaving the loop by `throw`, `break`
            // or `return` does not close the connection, so close it explicitly.
            await socket.close()
            throw error
        }
    } catch let error as HWebSocketError {
        // Thrown by connect(), send, ping() and the stream (connection lost without a close frame).
        print(error.localizedDescription)
    } catch {
        print(error)
    }
}

func leave(_ socket: HWebSocket) async {
    await socket.close(code: .normalClosure, reason: Data("bye".utf8))   // idempotent
}
```

Lifecycle rules:

- `messages` **finishes** when the connection closes through a close frame, sent by the server or by `close(code:reason:)`; `state` becomes `.closed(code:reason:)` with that code.
- `messages` **throws** an `HWebSocketError` when the connection is lost without a close frame (`.networkFailure`, `.unknown` with the POSIX error, `.pingTimeout`, `.messageTooBig`); `state` is `.closed(code: .abnormalClosure, reason: nil)`.
- Messages are read continuously and buffered until iterated, so close frames and pings are handled even while the app is not reading.
- Cancelling the task that iterates `messages` closes the connection with `.goingAway`. Leaving the loop any other way (`break`, `return`, a `throw` of your own such as a failed `decode`) does **not** close it: call `close()`.
- `send` and `ping()` on a closed connection throw `.notConnected`.
- A connection stays open (and the `HWebSocket` alive) until it is closed by either side: call `close()` when done, as with a `URLSessionTask`.

## Keep-alive pings

```swift
func configurePings() async {
    await HarborWebSocket.setDefaultPingInterval(30)   // nil (default): no pings
}

struct PricesSocket: HWebSocketRequestProtocol {
    let url = "wss://prices.example.com"
    let pingInterval: TimeInterval? = 15               // overrides the default for this socket
}

func manualPing(_ socket: HWebSocket) async throws {
    try await socket.ping()                             // waits for the pong (pingInterval, or 10 s without one)
}
```

A ping is sent every `pingInterval` seconds, regardless of traffic; when the pong does not arrive within the same interval the connection is closed and `messages` throws `.pingTimeout`. `ping()` applies the same timeout (`HWebSocket.defaultPingTimeout`, 10 seconds, when the request has no `pingInterval`) and throws `.pingTimeout` after closing the connection, so it can be used to probe a half-open link.

## Authentication

Same provider and flow as REST requests (`security.md`): with `needsAuth`, the handshake carries `getAuthorizationHeader()`. A `401` re-sends the handshake with the provider's current header when it already changed, otherwise calls `authFailed()` once and re-sends once with the refreshed header; a second rejection fails with `.authNeeded`. Without a provider, `.authProviderNeeded`.

```swift
struct FeedSocket: HWebSocketRequestProtocol {
    let url = "wss://api.example.com/feed"
    let needsAuth = true
}
```

## Handshake retries

`retryPolicy` applies to the handshake only. Retryable statuses (`retryableStatusCodes`, honoring `Retry-After` up to `HRetryPolicy.maxDelay`) and transient `URLError`s are retried; other statuses fail with `.handshakeFailed(statusCode:)` right away. Pin mismatches and certificate errors (`.certificate`) are never retried.

```swift
struct ResilientSocket: HWebSocketRequestProtocol {
    let url = "wss://api.example.com/live"
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3)
}
```

## Reconnecting

The example uses SwiftUI (`import SwiftUI`).

An `HWebSocket` is one connection and is never reconnected automatically: after a disconnect the app decides whether to resume, and from where. A loop with `HRetryPolicy.delay(forRetry:)` for the backoff:

```swift
@MainActor
final class LiveFeed: ObservableObject {
    @Published var events: [ChatEvent] = []
    private let policy = HRetryPolicy(maxRetries: 5, baseDelay: 1, multiplier: 2)

    func run() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                let socket = try await ChatSocket(room: "swift").connect()
                failures = 0
                do {
                    for try await message in socket.messages {
                        events.append(try message.decode(ChatEvent.self))
                    }
                } catch {
                    await socket.close()   // a failed decode leaves the loop with the socket open
                    throw error
                }
                // Server closed the connection with a close frame: reconnect unless told not to.
                if case .closed(let code, _) = await socket.state, code == .policyViolation { return }
            } catch {
                failures += 1
                guard failures <= policy.maxRetries else { return }
                try? await Task.sleep(nanoseconds: UInt64(policy.delay(forRetry: failures) * 1_000_000_000))
            }
        }
    }
}

struct FeedView: View {
    @StateObject private var feed = LiveFeed()

    var body: some View {
        List(feed.events, id: \.text) { Text($0.text) }
            .task { await feed.run() }   // cancelling the task closes the socket (.goingAway)
    }
}
```

## Errors

```swift
func handle(_ error: HWebSocketError) {
    switch error {
    case .handshakeFailed(let statusCode):
        print("Server answered \(statusCode) instead of 101")
    case .authNeeded, .authProviderNeeded:
        print("Auth problem")
    case .notConnected:
        print("Send or ping on a closed connection")
    case .pingTimeout:
        print("No pong: the connection was closed")
    case .messageTooBig:
        print("A message exceeded maximumMessageSize")
    case .invalidURL(let reason):
        print(reason)
    case .codable(let model, let underlying):
        print("Coding error in \(model): \(underlying)")
    case .noConnection, .timeout, .cannotFindHost, .cannotConnectToHost, .networkFailure:
        print("Network problem")
    case .certificate:
        print("TLS / pinning failure")
    case .cancelled, .unknown:
        print(error.localizedDescription)
    }
}
```

`HWebSocketError` conforms to `Error`, `Sendable`, `LocalizedError` and `Equatable`. `connect()`, `send`, `ping()` and `decode(_:)` use typed throws (`throws(HWebSocketError)`); `messages` throws `any Error` that is always an `HWebSocketError`.

## Debug logging

```swift
struct DebugChatSocket: HWebSocketRequestProtocol, HDebugRequestProtocol {
    let url = "wss://chat.example.com"
    let debugType: HDebugRequestType = .requestAndResponse
}
```

`.request` logs the handshake (URL and headers, redacted) and sent messages; `.response` logs the open event, received messages and the close. Errors are logged for every type. Message payloads are redacted like response bodies and truncated at 16 K characters.

## Testing

`HMock` does not apply to WebSocket connections. Test against a loopback server: Harbor's own suite uses an `NWListener` with `NWProtocolWebSocket` (`Tests/HarborWebSocketTests/Helpers/LoopbackWebSocketServer.swift`) for real handshakes, messages, pings and close frames, and a raw HTTP responder (`LoopbackHTTPResponder.swift`) for rejected handshakes (`401`, `503`, timeouts). Both are small enough to copy into an app's test target.

## Related files

- `Sources/HarborWebSocket/HarborWebSocket.swift`: `setDefaultPingInterval(_:)`.
- `Sources/HarborWebSocket/Request/HWebSocketRequestProtocol.swift`, `HWebSocketManager.swift` (handshake pipeline), `HWebSocketError.swift`.
- `Sources/HarborWebSocket/Connection/HWebSocket.swift` (the connection actor), `HWebSocketTaskDelegate.swift`, `HWebSocketMessage.swift`, `HWebSocketState.swift`.
