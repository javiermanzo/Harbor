---
name: harbor-websocket
description: Use when writing, reviewing or debugging Swift code that opens WebSocket connections with Harbor (import HarborWebSocket) - HWebSocketRequestProtocol, connect(), the HWebSocket actor (messages, send, send(json:), ping, close), HWebSocketMessage, HWebSocketState, HWebSocketError, subprotocols, keep-alive pings (setDefaultPingInterval), reconnection, or testing against a loopback server. For auth, pinning, mTLS, retry policy and logging see harbor-core; for REST requests see harbor.
---

# HarborWebSocket

`HarborWebSocket` opens WebSocket connections (RFC 6455). The handshake goes through Harbor's pipeline: connectivity check, auth provider (with the `401` refresh flow), default headers, retry policy, SSL pinning, mTLS, custom session and opt-in logging. The open connection is an `HWebSocket` actor that streams incoming messages and sends yours. `import HarborWebSocket` also brings the shared configuration (`harbor-core` skill); it doesn't need the REST product.

## Core rules

1. **Requests are structs.** Conform to `HWebSocketRequestProtocol`; only `url` is required (`ws`, `wss`, `http` or `https`; http(s) is rewritten to ws(s)). Defaults: `pathParameters`, `queryParameters`, `headerParameters` (`nil`), `subprotocols` (`[]`), `needsAuth` (`false`), `retryPolicy`, `timeoutInterval`, `pingInterval`, `maximumMessageSize` (`nil`).
2. **Everything throws `HWebSocketError`.** `connect()`, `send`, `ping()` and `decode(_:)` use typed throws; the `messages` stream throws `any Error` that is always an `HWebSocketError`.
3. **Iterate `messages` from one place.** It finishes on a close frame (code in `state`) and throws `.connectionFailed`, `.pingTimeout` or `.messageTooBig` when the connection is lost without one. Iterating it from two tasks at once traps.
4. **Close what you open.** Cancelling the task iterating `messages` closes the connection (`.goingAway`). Leaving the loop by `break`, `return` or a `throw` of your own (a failed `decode`) does not: call `close()`.
5. **No automatic reconnection.** `retryPolicy` retries the handshake only. After a disconnect, the app decides whether to connect again (`examples.md`, Reconnecting).

```swift
import HarborWebSocket

struct ChatSocket: HWebSocketRequestProtocol {
    let url = "wss://chat.example.com/rooms/{room}"
    let pathParameters: [String: String]?
    let needsAuth = true
    let pingInterval: TimeInterval? = 30

    init(room: String) {
        pathParameters = ["room": room]
    }
}

struct ChatEvent: Codable, Sendable {
    let user: String
    let text: String
}

func chat() async throws {
    let socket = try await ChatSocket(room: "swift").connect()
    try await socket.send("hello")
    do {
        for try await message in socket.messages {
            let event = try message.decode(ChatEvent.self)
            print(event.user, event.text)
        }
    } catch {
        await socket.close()   // a failed decode leaves the loop with the connection open
        throw error
    }
}
```

## Gotchas

- `send` and `ping()` on a closed connection, or racing its close, throw `.notConnected`.
- With a ping interval (the request's `pingInterval`, else `HarborWebSocket.setDefaultPingInterval(_:)`), a ping is sent every interval regardless of traffic; a missing pong closes the connection and `messages` throws `.pingTimeout`. `ping()` waits for the pong for that interval, or 10 s without one.
- Messages are read continuously and buffered until iterated, so close frames and pings are handled even while the app is not reading. The buffer has no limit: close a connection whose messages you stop reading.
- `close(code:reason:)` sends codes reserved for reporting (`.abnormalClosure`, `.noStatusReceived`, ...) as `.normalClosure` and cuts the reason to 123 bytes; `state` records what was sent.
- Subprotocols are treated as credentials: redacted in logs and stripped from cross-origin redirects.
- A handshake status other than `101` fails with `.handshakeFailed(statusCode:)` after the retry policy, except `401`, which goes through the auth refresh and ends in `.authNeeded` when it cannot be recovered.
- `HMock` and `URLProtocol` stubs don't apply to WebSocket tasks: test against a loopback server (`examples.md`, Testing).

## Where to look

| Need | Read |
|---|---|
| Requirements table, connecting, sending, lifecycle, pings, auth, handshake retries, reconnection, errors, logging, testing | `examples.md` |
| Auth provider and `401` refresh, pinning, mTLS, custom `URLSession`, `HRetryPolicy`, logging | `../harbor-core/SKILL.md` |
| Handshake pipeline and connection actor internals | `../harbor-core/architecture.md` (WebSocket connections) |
