# Harbor Architecture

How a request moves through Harbor, and where each concern lives in `Sources/`.

## Modules

| Module | Purpose | Key files |
|---|---|---|
| `HarborCore` (not a product) | What several products share: auth provider and refresh, pinning/mTLS/redirects, logging and redaction, session pool, retry policy and attempt loop, URL composition, shared `Harbor.setX(_:)` setters | `Harbor.swift`, `Auth/`, `Config/`, `Debug/`, `Request/`, `Utils/` |
| `Harbor` | REST requests, cache, mocks, multipart, request execution (re-exports `HarborCore`) | `Harbor+REST.swift`, `Request/`, `Cache/`, `Config/`, `Debug/`, `Mock/`, `Utils/` |
| `HarborJRPC` | JSON-RPC 2.0 on top of Harbor's REST pipeline | `HarborJRPC.swift`, `Request/`, `Config/` |
| `HarborWebSocket` | WebSocket connections on top of `HarborCore` only (re-exports it) | `HarborWebSocket.swift`, `Request/`, `Connection/`, `Config/`, `Debug/` |

```text
HarborCore ◄── Harbor ◄── HarborJRPC
    ▲
    └────────── HarborWebSocket
```

`HarborCore` and `Harbor` depend on [LogBird](https://github.com/javiermanzo/LogBird) (`from: "2.1.0"`) for logging, behind the `HLogger` facade. `HarborCore` is not a product: its internals (`HConfig`, `HLogger`, `HRedactionPolicy`, the session pool, the auth refresh, the attempt loop and the error mapping of `HRequestManager`, `HURLBuilder.compositeURL`) are `package`, and the types that were already public (`HRetryPolicy`, `HRequestError`, `HAuthProviderProtocol`, `HDebugRequestProtocol`, `HMTLS`, `HURLSessionDelegate`, the shared `Harbor` setters, ...) are re-exported with `@_exported import HarborCore` by `Harbor` and `HarborWebSocket`. A WebSocket-only app therefore links no cache, mocks, request protocols or multipart code, and can still call `Harbor.setAuthProvider(_:)`. `HarborJRPC` stays on `Harbor` because a JSON-RPC call is a REST POST.

## Protocol hierarchy

```text
HRequestBaseRequestProtocol            url, httpMethod, needsAuth, retryPolicy,
│                                      pathParameters, headerParameters, timeoutInterval
├── HRequestWithResultProtocol         associatedtype Model: HModel; parseData; request() -> HResponseWithResult<Model>
│   └── HGetRequestProtocol            queryParameters, cacheType, shouldCache(statusCode:), cache(), requestStream(source:)
└── HRequestWithEmptyResponseProtocol  request() -> HResponse
    ├── HRequestWithBodyProtocol       bodyParameters, multipartBody, rawBody (first non-nil of rawBody, multipartBody, bodyParameters)
    │   ├── HPostRequestProtocol
    │   ├── HPutRequestProtocol
    │   └── HPatchRequestProtocol
    └── HDeleteRequestProtocol

HDebugRequestProtocol                  debugType (opt-in logging, combine with any request)
HAuthProviderProtocol                  getAuthorizationHeader(), authFailed()
HJRPCRequestProtocol (HarborJRPC)      method, parameters, request() async throws -> Model
HWebSocketRequestProtocol (HarborWebSocket)  url, subprotocols, pingInterval, connect() async throws(HWebSocketError) -> HWebSocket
```

`HModel` is `Codable & Sendable`. All requirements are get-only, and protocol extensions supply the defaults (see `protocols.md`).

## Concurrency model

- `@globalActor public actor HRequestManagerActor` serializes all of Harbor's mutable state.
- `public enum Harbor` (the configuration API) and the internal `HRequestManager`, `HConfig` (`HConfig.shared`, shared) and `HRESTConfig` (REST only), `HMocker`, `HarborJRPC` and `HarborWebSocket` (with its `HWebSocketManager`) are isolated to that actor. That's why every `Harbor.setX(...)` call needs `await` from outside the actor.
- Each open WebSocket connection is its own actor (`HWebSocket`): its send/receive state is independent of the global actor, which only runs the handshake.
- Response decoding (`parseData(data:model:)`) runs off the actor, in a `nonisolated` function, so concurrent requests don't serialize their decoding.
- The cache manager (`HCache.Manager.shared`) keeps memory and index state on the actor and does disk I/O on a concurrent queue (writes and deletes under a barrier).
- Requests, models, policies and errors are `Sendable`. A request can be a struct with computed `bodyParameters`, so no `@unchecked Sendable` is needed.

## Request flow (`HRequestManager`)

```text
request()
 ├─ mocks enabled && mock registered for type(of: request)?
 │    └─ run the attempt loop with mock attempts (mock resolved on every attempt,
 │       so an HMockSequence advances across retries and 401 re-attempts)
 ├─ offline (NWPathMonitor path is .unsatisfied)?
 │    └─ GET: serve a fresh custom-cache entry / URLCache response / stale-if-error entry,
 │       else fail with .noConnection (needsAuth lookup rules: cache.md)
 ├─ needsAuth? → authProvider.getAuthorizationHeader()  (no provider → .authProviderNeeded)
 └─ attempt loop (runAttempts)
      ├─ HURLBuilder.prepareRequest (+Request): URL + path/query encoding, timeout, cookies, body,
      │  default headers → request headers → auth header, conditional validators (custom cache)
      ├─ URLSession data/upload task with a per-task HTaskContext delegate
      ├─ 2xx  → decode off-actor, store in cache (GET; needsAuth: only under the credential it
      │         was sent with, never when sent without one; skipped if the request started
      │         before clearAllCache() / setAuthProvider(_:)) → .success
      ├─ 304  → serve + refresh the cached entry; if no cached body and Harbor injected the
      │         validators: re-send once without them (caller-set validators: .api(304))
      ├─ 401  → refresh the header once (HRequestManager+Auth; flow in security.md),
      │         re-send, else .authNeeded
      ├─ retryable status / URLError and attempts left → wait (Retry-After or backoff) → next attempt
      ├─ 5xx (GET, retries exhausted) → stale-if-error entry if available
      └─ otherwise → .error(HRequestError)
```

Notes:

- Worst-case attempts per request: `1 + retryPolicy.maxRetries + 1` (one extra attempt for an auth refresh).
- If Harbor's delegate rejects the TLS handshake (pin mismatch, untrusted chain, mTLS rejection) or the system reports a certificate-specific `URLError`, the error surfaces as `.certificate`. It is never retried and never masked by cached content. A generic `URLError.secureConnectionFailed` is `.networkFailure` instead and counts as a transient failure for retries.
- Cancelling the calling task ends the loop with `.cancelled`, including during a backoff sleep.
- Debug output is produced only for requests that conform to `HDebugRequestProtocol`, and only while logging is enabled.

## Connectivity

`HRequestManagerMonitor` wraps `NWPathMonitor` and starts lazily. Only a definitive `.unsatisfied` path blocks a request. `.requiresConnection` and "no update received yet" let the request through. In DEBUG/simulator builds requests are always allowed unless `Harbor.setAssumeNetworkAvailableInDebug(false)` is set. The internal `Harbor.stopNetworkMonitor()` (tests only, via `@testable import`) resets it.

## URLSession management

- With `Harbor.setCustomURLSession(_:)` set, that session is used as-is for every request. Harbor's pinning, mTLS and redirect policy apply only if its delegate is `Harbor.makeURLSessionDelegate()` (or forwards to one).
- Otherwise Harbor builds sessions with `HURLSessionDelegate` and caches up to **4** of them, keyed by cache configuration and cookie handling. When the limit is reached, only the least recently used session is dropped; it is invalidated once no in-flight attempt holds it, and rebuilt on demand. Changing timeouts, mTLS, pins or cookie handling retires all of them the same way.
- The per-request timeout (`timeoutInterval` or the default) is set on each `URLRequest`, so it also applies to custom sessions. `setDefaultResourceTimeoutInterval(_:)` applies only to Harbor-built sessions.
- Requests with a `.custom` or `.disabled` cache type use sessions isolated from `URLCache.shared`.
- WebSocket connections lease a session of their own (no `URLCache`, no resource timeout: a connection may stay open longer than any transfer) for as long as they are open, so a configuration change meanwhile retires the session without invalidating it under the task. A custom session is used as-is, as for REST.

## JSON-RPC adapter

`HJRPCRequestProtocol` requests are wrapped in an internal `HPostRequestProtocol & HRequestWithResultProtocol` struct whose `rawBody` is the encoded JSON-RPC envelope (`jsonrpc`, `method`, `id`, `params`). They go through the same pipeline: auth, retry, logging (when the JSON-RPC request conforms to `HDebugRequestProtocol`) and transport security. Batches use another internal wrapper. See `examples/jrpc.md`.

## WebSocket connections

```text
connect()
 ├─ HURLBuilder.compositeURL (ws/wss/http/https; http(s) rewritten to ws(s))
 ├─ offline (path .unsatisfied)? → .noConnection
 ├─ needsAuth → provider header (no provider → .authProviderNeeded)
 └─ handshake attempt loop (retryPolicy; treated as idempotent)
      ├─ URLRequest: timeout, cookies flag, default headers → request headers →
      │  Sec-WebSocket-Protocol → auth header
      ├─ leased session + URLSessionWebSocketTask with a per-task HWebSocketTaskDelegate
      │  (records didOpen / didClose / didComplete and TLS rejections; HURLSessionDelegate
      │  keeps handling challenges through the package HTaskDelegateContext protocol)
      ├─ open  → HWebSocket actor (receive loop + optional ping loop) → return
      ├─ 401   → HRequestManager.refreshAuthorization (same rules as REST), re-send once
      │  (the loop itself is HRequestManager.runAttemptLoop, shared with REST requests)
      ├─ other non-101 status → retry per policy / Retry-After, else .handshakeFailed
      └─ URLError → mapTransportError (.certificate never retried), retry if transient
```

`HWebSocket` reads messages continuously into an unbounded `AsyncThrowingStream`. When `receive()` fails it waits (bounded) for the task completion, then ends the stream normally if a close frame was recorded (`task.closeCode` or the delegate's `didCloseWith`), or throws the mapped error otherwise. `close(code:reason:)` cancels the task with the close code, finishes the stream and releases the session lease. Keep-alive pings race `sendPing` against a timer: a missing pong closes the connection with `.pingTimeout`, while a ping that fails with an error leaves the classification to the receive loop (the connection is closing or lost). See `examples/websocket.md`.

## Related files

- `Sources/HarborCore/Request/HRequestManager.swift` (global actor, shared state and attempt outcomes) and its shared extensions: `+Auth` (authorization, refresh), `+AttemptLoop` (retry/401 loop used by REST and WebSocket), `+Retry` (error mapping, `Retry-After`, backoff), `+URLSessionPool` (session cache, `HSessionProfile`). REST-only extensions in `Sources/Harbor/Request/`: `+Execution` (request flows), `+Mock`, `+RESTSession` (request to session profile), `+RESTState` (remembered credentials, cache generation).
- `Sources/Harbor/Request/HGetRequestProtocol.swift` (defaults, `requestStream`) and the other protocol files (one per protocol).
- `Sources/HarborCore/Request/HRetryPolicy.swift`: retry classification.
- `Sources/HarborCore/Utils/HURLBuilder.swift`: URL composition and encoding (shared); `Sources/Harbor/Utils/HURLBuilder+Request.swift`: header, body, multipart and cache-validator construction (REST).
- `Sources/HarborCore/Request/HURLSessionDelegate.swift`: pinning, mTLS, redirects.
- `Sources/HarborCore/Config/HConfig.swift`: global state shared by every product; `Sources/Harbor/Config/HRESTConfig.swift`: REST-only state (cache type, mocks, JSON decoder).
- `Sources/HarborJRPC/Request/HJRPCRequestManager.swift`: JSON-RPC execution and batches.
- `Sources/HarborWebSocket/Request/HWebSocketManager.swift`: handshake pipeline; `Sources/HarborWebSocket/Connection/HWebSocket.swift`: the connection actor; `HWebSocketTaskDelegate.swift`: task delegate.
