# HarborWebSocket design

Date: 2026-10-16. Target branch: `release/4.0.0`.

## Intent

Harbor covers REST (`Harbor`) and JSON-RPC 2.0 (`HarborJRPC`). Apps that need real-time data today pull in Starscream or hand-roll `URLSessionWebSocketTask` loops, losing Harbor's auth provider, SSL pinning, mTLS, retry and logging. `HarborWebSocket` adds WebSocket connections (RFC 6455) as a third product with the same philosophy: a `Sendable` request struct conforming to a protocol, one call to open the connection, `async/await` everywhere, no delegates and no callbacks.

## Research summary

- **Starscream** (daltoniam): last release 4.0.8 (March 2024), last commit May 2024. Delegate/closure based, GCD, no `async/await`, no Swift 6 concurrency. Its feature list is still the reference for what a client needs: custom headers, subprotocol negotiation, pinning, automatic pong replies, close codes, compression. It is not a code base to build on.
- **Transport choice**: `URLSessionWebSocketTask` (iOS 13+/macOS 10.15+). It is the only transport that reuses Harbor's existing security stack for free: `HURLSessionDelegate` handles pinning, mTLS and the cross-origin redirect policy for WebSocket tasks exactly like for data tasks; custom sessions (`Harbor.setCustomURLSession`) and cookies work unchanged. Apple now steers developers to Network.framework's `NetworkConnection` (WWDC25 session 250), but that API is iOS 26+, so it cannot back a library targeting iOS 15+; `NWConnection` + `NWProtocolWebSocket` (iOS 13+) would need a parallel implementation of pinning/mTLS through `sec_protocol_options` and would bypass custom sessions.
- **Known `URLSessionWebSocketTask` pitfalls** the design accounts for:
  - `receive()` returns one message; a loop is needed, and only one `receive()` should be pending.
  - `sendPing(pongReceiveHandler:)` has no `async` form; the handler was reported to fire twice (Apple forums thread 756482). The wrapper resumes its continuation once.
  - After a server close frame, `receive()` fails with `NSPOSIXErrorDomain 57` ("socket is not connected") while `task.closeCode`/`closeReason` carry the frame. A connection cut without a close frame reports `closeCode == .invalid` with `state == .completed` (FB17252543). The library distinguishes both cases.
  - A handshake rejected with a non-101 status fails `receive()` with `URLError.badServerResponse`; the status is only available through `task.response`.
  - `cancel(with:reason:)` occasionally reaches the server as 1006 (forum thread 679446). Framework bug; not mitigated.
  - Task-specific delegates (`task.delegate`, iOS 15+) receive `didOpenWithProtocol`/`didCloseWith`. Verified in a spike against a loopback `NWProtocolWebSocket` server; the spike also showed that `NWProtocolWebSocket.Response(status: .reject)` hangs the client, so rejected handshakes are tested with a raw HTTP server instead.

## Goals

1. `struct ChatSocket: HWebSocketRequestProtocol { let url = "wss://..." }` then `let socket = try await ChatSocket().connect()`.
2. Same pipeline guarantees as REST: connectivity pre-check, auth provider header (and the 401 refresh flow), `HRetryPolicy` for the handshake, default headers, timeouts, pinning/mTLS/custom session, opt-in logging with redaction.
3. `AsyncThrowingStream` of typed messages, `send` for text/data/`Encodable`, explicit `close(code:reason:)`, optional keep-alive pings with a pong timeout.
4. Swift 6 strict concurrency, no `@unchecked Sendable` in public types, every public symbol documented.
5. Real-transport tests on a loopback server; no network needed.

## Non-goals (v1)

- Automatic reconnection and offline message queues. The connection object represents one socket; the skill documents a reconnection loop built on `HRetryPolicy.delay(forRetry:)`. Reconnecting transparently hides message gaps and needs app-level resume semantics that vary per protocol.
- `HMock` support. Mocks short-circuit the REST pipeline; WebSocket tests use the loopback server (shipped as a test helper and documented pattern).
- Compression negotiation, custom extensions, proxies: whatever `URLSession` does is what the library does.
- A `HarborCore` module. Swift's `package` access level gives `HarborWebSocket` access to Harbor's internals (`HConfig`, `HLogger`, `HRedactionPolicy`, session pool, auth refresh, error mapping) without exposing them publicly and without splitting modules. The affected declarations change from `internal` to `package`; nothing moves.

## Anti-goals

- A second configuration surface. All network-level settings stay on `Harbor`; `HarborWebSocket` only adds `setDefaultPingInterval(_:)`.
- Leaking credentials in logs. Handshake headers and the URL go through `HRedactionPolicy`; message payloads are logged only for requests that opt in through `HDebugRequestProtocol`, redacted and truncated like REST bodies.
- Weakening the security defaults: WebSocket tasks run on the same `HURLSessionDelegate` as REST, so pin mismatches and mTLS rejections surface as `.certificate` and are never retried.

## Public API

```swift
import HarborWebSocket

public protocol HWebSocketRequestProtocol: Sendable {
    var url: String { get }                              // ws, wss, http or https (http(s) is rewritten to ws(s))
    var pathParameters: [String: String]? { get }        // nil
    var queryParameters: [String: String]? { get }       // nil
    var headerParameters: [String: String]? { get }      // nil
    var subprotocols: [String] { get }                   // [] (Sec-WebSocket-Protocol)
    var needsAuth: Bool { get }                          // false
    var retryPolicy: HRetryPolicy? { get }               // nil; handshake only
    var timeoutInterval: TimeInterval? { get }           // nil → Harbor default (handshake)
    var pingInterval: TimeInterval? { get }              // nil → HarborWebSocket default (nil = no pings)
    var maximumMessageSize: Int? { get }                 // nil → system default (1 MiB)

    func connect() async throws(HWebSocketError) -> HWebSocket
}

public actor HWebSocket {
    public nonisolated let messages: AsyncThrowingStream<HWebSocketMessage, Error>   // single consumer
    public nonisolated let negotiatedSubprotocol: String?
    public var state: HWebSocketState                     // .open | .closed(code:reason:)

    public func send(_ text: String) async throws(HWebSocketError)
    public func send(_ data: Data) async throws(HWebSocketError)
    public func send<T: Encodable & Sendable>(json value: T, encoder: JSONEncoder = JSONEncoder()) async throws(HWebSocketError)
    public func ping() async throws(HWebSocketError)
    public func close(code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: Data? = nil) async
}

public enum HWebSocketMessage: Sendable, Equatable {
    case text(String)
    case data(Data)
    public func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder = JSONDecoder()) throws(HWebSocketError) -> T
}

public enum HWebSocketState: Sendable, Equatable {
    case open
    case closed(code: URLSessionWebSocketTask.CloseCode, reason: Data?)
}

public enum HWebSocketError: Error, LocalizedError, Equatable, Sendable {
    case handshakeFailed(statusCode: Int)                 // non-101 handshake status that is not 401
    case notConnected                                     // send/ping on a closed socket
    case pingTimeout                                      // no pong within pingTimeout → socket closed with .abnormalClosure
    case invalidURL(reason: String)                       // malformed URL / unsupported scheme
    case codable(modelName: String, error: Error)         // send(json:) / decode(_:)
    // mirrored from HRequestError:
    case authProviderNeeded, authNeeded, noConnection, timeout, cannotFindHost, cannotConnectToHost,
         cancelled, certificate, networkFailure(URLError), unknown(Error)
}

@HRequestManagerActor
public enum HarborWebSocket {
    public static func setDefaultPingInterval(_ interval: TimeInterval?)   // nil (default): no keep-alive pings
}
```

Why `throws` instead of `Result`: like JSON-RPC, a socket has several failing operations (`connect`, `send`, `ping`, the stream) and wrapping each in a `Result` would be noise. Typed throws (`throws(HWebSocketError)`) keep the catch site precise. AGENTS.md rule 2 is updated to list the exception.

Stream semantics:
- Messages are buffered (unbounded) by an internal receive loop started on connect, so close frames, pings and pongs are processed even while the app is not reading.
- The stream **finishes normally** when the connection closes through a close frame (sent by either side) or `close()`; `state` carries the code and reason. It **throws** `HWebSocketError` when the transport fails without a close frame (connection lost, TLS failure, ping timeout, cancellation), and `state` becomes `.closed(code: .abnormalClosure, reason: nil)`.
- Iterate it once. `AsyncThrowingStream` hands each element to one consumer.

Keep-alive: with `pingInterval` set, the socket sends a ping every interval after the last ping; a pong that does not arrive within the same interval closes the socket (`.abnormalClosure`) and the stream throws `.pingTimeout`. Manual `ping()` is available regardless.

Closing: `close(code:reason:)` sends the close frame through `cancel(with:reason:)`, cancels the loops, finishes the stream and sets `state`. It is idempotent. A deallocated `HWebSocket` whose socket is still open cancels the task with `.goingAway`.

## Connection pipeline (`HWebSocketManager`, isolated to `@HRequestManagerActor`)

```text
connect()
 ├─ build URL: HURLBuilder.compositeURL (path/query encoding) accepting ws/wss/http/https; http(s) → ws(s)
 ├─ offline (path .unsatisfied)? → .noConnection
 ├─ needsAuth → provider header (no provider → .authProviderNeeded)
 └─ attempt loop (handshake only; retryPolicy, method treated as GET = idempotent)
      ├─ URLRequest: timeout, cookies flag, default headers → request headers → Sec-WebSocket-Protocol → auth header
      ├─ lease a Harbor session (same pool as REST, non-GET signature), create the task with the
      │  per-task HWebSocketTaskDelegate, resume, await didOpen / didComplete
      ├─ open   → HWebSocket (holds the session lease until closed) → return
      ├─ 401    → HRequestManager.refreshAuthorization (same rules as REST), retry once
      ├─ other status → .handshakeFailed(statusCode) unless retryable (retryableStatusCodes, Retry-After)
      ├─ URLError → mapTransportError (.certificate when the delegate rejected TLS; never retried) → retry if transient
      └─ cancellation → .cancelled
```

The per-task delegate (`HWebSocketTaskDelegate`) records the negotiated protocol, the close frame and TLS rejections; `HURLSessionDelegate` learns about it through a new `package` protocol (`HTaskDelegateContext`) that `HTaskContext` adopts too.

## Harbor changes (internal → `package`)

- `HConfig` (`shared`, `authProvider`, `defaultHeaderParameters`, `timeoutInterval`, `httpShouldHandleCookies`).
- `HLogger.log`, `HLogger.isLoggingEnabled`; `HRedactionPolicy` (`current`, `redactedHeaders`, `redactedURLString`, `redactedBody`, `placeholder`, `registerAuthHeaderKey`).
- `HRequestManager`: `connectivityMonitor`, `authorizationHeader(needsAuth:)`, `refreshAuthorization`, `HAuthRefresh`, `leaseURLSession()` / `releaseURLSession(_:)` (non-request overload), `mapTransportError`, `mapNonURLError`, `statusRetry`, `sleep(seconds:)`.
- `HRetryPolicy.shouldRetry(statusCode:method:)`, `shouldRetry(urlError:method:)`.
- `HURLBuilder.compositeURL(url:pathParameters:queryParameters:allowedSchemes:)`.
- `HTaskContext` → conforms to `package protocol HTaskDelegateContext { var authHeaderKey; func recordTrustFailure() }`; `HURLSessionDelegate` looks up that protocol.
- `HLockedState`.

No public API of `Harbor` changes.

## Files

```text
Sources/HarborWebSocket/
  HarborWebSocket.swift                      public enum: setDefaultPingInterval
  Config/HWebSocketConfig.swift              @HRequestManagerActor struct, shared
  Request/HWebSocketRequestProtocol.swift    protocol, defaults, connect()
  Request/HWebSocketManager.swift            handshake pipeline (auth, retry, session lease)
  Request/HWebSocketError.swift
  Connection/HWebSocket.swift                public actor
  Connection/HWebSocketTaskDelegate.swift    URLSessionWebSocketDelegate per task
  Connection/HWebSocketMessage.swift
  Connection/HWebSocketState.swift
Tests/HarborWebSocketTests/
  Helpers/LoopbackWebSocketServer.swift      NWListener + NWProtocolWebSocket
  Helpers/LoopbackHTTPResponder.swift        raw HTTP server for rejected handshakes
  HarborWebSocketTests.swift, ...
```

Docs: README (WebSocket section + TOC + install snippet), `.agents/skills/harbor/` (SKILL.md, architecture.md, protocols.md, examples/websocket.md, testing.md), AGENTS.md (products, rule 2, `package` note), CHANGELOG `[Unreleased]`, Example app (WebSocket section against `wss://echo.websocket.org`).

## Left to the builder

- Exact log messages and the fields logged per event (handshake, open, message, close, error).
- Buffer policy constant and the `maximumMessageSize` validation (`> 0`).
- Whether the Example app demo uses a public echo service or a bundled loopback server (decided: public echo service, with a clear error when offline).
