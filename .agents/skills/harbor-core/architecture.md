# Harbor Architecture

How a request moves through Harbor, and where each concern lives in `Sources/`.

## Modules

| Module | Purpose | Key files |
|---|---|---|
| `HarborCore` (not a product) | What several products share: auth provider and refresh, pinning/mTLS/redirects, logging and redaction, session pool, retry policy and attempt loop, URL composition, shared `Harbor.setX(_:)` setters | `Harbor.swift`, `Auth/`, `Config/`, `Debug/`, `Request/`, `Utils/` |
| `Harbor` | REST requests, cache, mocks, multipart, request execution (re-exports `HarborCore`) | `Harbor+REST.swift`, `Request/`, `Cache/`, `Config/`, `Debug/`, `Mock/`, `Utils/` |
| `HarborJRPC` | JSON-RPC 2.0 on top of Harbor's REST pipeline (re-exports `Harbor`) | `HarborJRPC.swift`, `HarborExports.swift`, `Request/`, `Config/` |
| `HarborWebSocket` | WebSocket connections on top of `HarborCore` only (re-exports it) | `HarborWebSocket.swift`, `Request/`, `Connection/`, `Config/`, `Debug/` |

```text
HarborCore ◄── Harbor ◄── HarborJRPC
    ▲
    └────────── HarborWebSocket
```

Only `HarborCore` depends on [LogBird](https://github.com/javiermanzo/LogBird) (`from: "2.1.0"`) for logging. The products log through the `HLogger` facade with Harbor's own `HLogLevel`, `HLogValue` and `HLogExtraMessage`, without importing LogBird; inside HarborCore only the SSL and PKCS#12 diagnostics loggers and the redaction defaults use LogBird directly. `HarborCore` is not a product: its internals (`HConfig`, `HLogger`, `HRedactionPolicy`, the session pool, the auth refresh, the attempt loop and the error mapping of `HRequestManager`, `HURLBuilder.compositeURL`) are `package`, and the types that were already public (`HRetryPolicy`, `HRequestError`, `HAuthProviderProtocol`, `HDebugRequestProtocol`, `HMTLS`, `HURLSessionDelegate`, the shared `Harbor` setters, ...) are re-exported with `@_exported import HarborCore` by `Harbor` and `HarborWebSocket` (`HarborJRPC` gets them through `Harbor`). A WebSocket-only app therefore links no cache, mocks, request protocols or multipart code, and can still call `Harbor.setAuthProvider(_:)`. `HarborJRPC` stays on `Harbor` because a JSON-RPC call is a REST POST, and re-exports it (`@_exported import Harbor`), so `import HarborJRPC` is enough too.

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
HJRPCRequestProtocol (HarborJRPC)      method, parameters, timeoutInterval, request() async throws -> Model
HWebSocketRequestProtocol (HarborWebSocket)  url, subprotocols, pingInterval, connect() async throws(HWebSocketError) -> HWebSocket
```

`HModel` is `Codable & Sendable`. All requirements are get-only, and protocol extensions supply the defaults (see `../harbor/protocols.md`).

## Concurrency model

- `@globalActor public actor HRequestManagerActor` serializes all of Harbor's mutable state.
- The public `Harbor`, `HarborJRPC` and `HarborWebSocket` enums (the configuration APIs) and the internal `HRequestManager`, `HConfig` (`HConfig.shared`, shared), `HRESTConfig` (REST only), `HMocker`, `HJRPCRequestManager` (with its `config`) and `HWebSocketManager` / `HWebSocketConfig.shared` are isolated to that actor. That's why every `Harbor.setX(...)` call needs `await` from outside the actor.
- Each open WebSocket connection is its own actor (`HWebSocket`): its send/receive state is independent of the global actor, which only runs the handshake.
- Response decoding (`parseData(data:model:)`) runs off the actor, in a `nonisolated` function, so concurrent requests don't serialize their decoding. Cached bodies are decoded off the actor the same way.
- The cache manager (`HCache.Manager.shared`) keeps memory and index state on the actor and does disk I/O on a concurrent queue (writes and deletes under a barrier). A clear token and per-key removal counters keep a read or write that was suspended across a clear or a removal from bringing the entry back.
- State read before an `await` is re-checked after it where it matters: the cache generation (captured when a request starts), the auth generation (a `401` refresh gives up when the provider was replaced) and the mTLS generation (the latest `setMTLS(_:)` / `clearMTLS()` wins).
- Requests, models, policies and errors are `Sendable`. A request can be a struct with computed `bodyParameters`, so no `@unchecked Sendable` is needed.

## Request flow (`HRequestManager`)

```text
request()
 ├─ capture cacheGeneration (the response is only stored if it is unchanged when it is written)
 ├─ mocks enabled && mock registered for type(of: request)?
 │    └─ run the attempt loop with mock attempts (mock resolved on every attempt,
 │       so an HMockSequence advances across retries and 401 re-attempts; the provider's
 │       header is attached when needsAuth, no connectivity check, never .authProviderNeeded)
 ├─ offline (NWPathMonitor path is .unsatisfied)?
 │    └─ GET: serve a fresh custom-cache entry / URLCache response / stale-if-error entry,
 │       else fail with .noConnection (needsAuth lookup rules: ../harbor/cache.md)
 ├─ needsAuth? → authProvider.getAuthorizationHeader()  (no provider → .authProviderNeeded)
 └─ attempt loop (runAttempts)
      ├─ HURLBuilder.prepareRequest (+Request): URL + path/query encoding, timeout, cookies, body,
      │  default headers → request headers → auth header, conditional validators (custom cache)
      ├─ URLSession data/upload task with a per-task HTaskContext delegate
      ├─ 2xx  → decode off-actor, store in cache (GET, shouldCache; keyed by the headers sent;
      │         needsAuth: only under the credential it was sent with, never when sent without
      │         one; skipped if clearAllCache() / setAuthProvider(_:) ran since the request
      │         started) → .success
      ├─ 304  → validators Harbor injected: serve + refresh the cached entry (same ETag only;
      │         no-store removes it); no servable body: re-send once without the validators.
      │         Caller-set validators: .api(304)
      ├─ 401  → refresh the header once (HRequestManager+Auth; flow in auth.md),
      │         re-send, else .authNeeded
      ├─ retryable status / URLError and attempts left → wait (Retry-After or backoff) → next attempt
      ├─ 5xx (GET, retries exhausted) → stale-if-error entry if available
      └─ otherwise → .error(HRequestError)
```

Notes:

- Worst-case attempts per request: `1 + retryPolicy.maxRetries + 1` (one extra attempt for an auth refresh).
- If Harbor's delegate rejects the TLS handshake (pin mismatch, untrusted chain, mTLS rejection) or the system reports a certificate-specific `URLError`, the error surfaces as `.certificate`. It is never retried and never masked by cached content. A generic `URLError.secureConnectionFailed` is `.networkFailure` instead and counts as a transient failure for retries.
- Cancelling the calling task ends the loop with `.cancelled`, including during a backoff sleep and while waiting for a shared `authFailed()`.
- Debug output is produced only for requests that conform to `HDebugRequestProtocol`, and only while logging is enabled.

## Connectivity

`HRequestManagerMonitor` wraps `NWPathMonitor` and starts lazily. Only a definitive `.unsatisfied` path blocks a request. `.requiresConnection` and "no update received yet" let the request through. In DEBUG/simulator builds requests are always allowed unless `Harbor.setAssumeNetworkAvailableInDebug(false)` is set. The internal `Harbor.stopNetworkMonitor()` (tests only, via `@testable import HarborCore`) resets it; an update from a stopped monitor is ignored.

## URLSession management

- With `Harbor.setCustomURLSession(_:)` set, that session is used as-is for every request. Harbor's pinning, mTLS and redirect policy apply only if its delegate is `Harbor.makeURLSessionDelegate()` (or forwards to one).
- Otherwise Harbor builds sessions with `HURLSessionDelegate` and caches up to **4** of them, keyed by cache configuration and cookie handling. When the limit is reached, only the least recently used session is dropped; it is invalidated once no in-flight attempt holds it, and rebuilt on demand. Changing timeouts, mTLS, pins or cookie handling retires all of them the same way.
- The per-request timeout (`timeoutInterval` or the default) is set on each `URLRequest`, so it also applies to custom sessions. `setDefaultResourceTimeoutInterval(_:)` applies only to Harbor-built sessions.
- Requests with a `.custom` or `.disabled` cache type use sessions isolated from `URLCache.shared`.
- WebSocket connections lease a session of their own (no `URLCache`, no resource timeout: a connection may stay open longer than any transfer) for as long as they are open, so a configuration change meanwhile retires the session without invalidating it under the task. A custom session is used as-is, as for REST.

## JSON-RPC adapter

`HJRPCRequestProtocol` requests are wrapped in an internal `HJRPCRequestWrapper` (`HPostRequestProtocol & HRequestWithResultProtocol`) whose `rawBody` is the encoded JSON-RPC envelope (`jsonrpc`, `method`, `id`, `params`). They go through the same pipeline: auth, retry, timeout, logging (when the JSON-RPC request conforms to `HDebugRequestProtocol`, through `HJRPCDebugRequest`, which names the app's request in the logs via the `package` `HLogNamedRequest` hook) and transport security. Batches use `HJRPCBatchWrapper`; their response elements are decoded one by one (a malformed element does not fail the others) and matched back to the requests by `id`, in request order. See `../harbor-jrpc/examples.md`.

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

`HWebSocket` reads messages continuously into an unbounded `AsyncThrowingStream` (message kinds it does not know are skipped). When `receive()` fails it waits (bounded) for the task completion, then ends the stream normally if a close frame was recorded (`task.closeCode` or the delegate's `didCloseWith`), or cancels the task and throws the mapped error otherwise: on an open connection everything but cancellation, a certificate rejection and an oversized message maps to `.connectionFailed`. `close(code:reason:)` sends reserved codes as `.normalClosure`, cuts the reason to 123 bytes, cancels the task with them, finishes the stream and releases the session lease. Keep-alive pings race `sendPing` against a timer: a missing pong closes the connection with `.pingTimeout` (unless the server's close frame arrived meanwhile), while a ping that fails with an error leaves the classification to the receive loop (the connection is closing or lost); `ping()` and `send` racing a close report `.notConnected`. See `../harbor-websocket/examples.md`.

## Related files

- `Sources/HarborCore/Request/HRequestManagerActor.swift` (the global actor) and `HRequestManager.swift` (shared state and attempt outcomes) and its shared extensions: `+Auth` (authorization, refresh), `+AttemptLoop` (retry/401 loop used by REST and WebSocket), `+Retry` (error mapping, `Retry-After`, backoff), `+URLSessionPool` (session cache, `HSessionProfile`). REST-only extensions in `Sources/Harbor/Request/`: `+Execution` (request flows), `+Mock`, `+RESTSession` (request to session profile), `+RESTState` (remembered credentials, cache generation).
- `Sources/Harbor/Request/HGetRequestProtocol.swift` (defaults, `requestStream`) and the other protocol files (one per protocol).
- `Sources/HarborCore/Request/HRetryPolicy.swift`: retry classification.
- `Sources/HarborCore/Utils/HURLBuilder.swift`: URL composition and encoding (shared); `Sources/Harbor/Utils/HURLBuilder+Request.swift`: header, body, multipart and cache-validator construction (REST).
- `Sources/HarborCore/Request/HURLSessionDelegate.swift`: pinning, mTLS, redirects; `HTaskDelegateContext.swift`: what it needs from a task delegate (adopted by `Sources/Harbor/Request/HTaskContext.swift` and `HWebSocketTaskDelegate`).
- `Sources/HarborCore/Request/HMTLS.swift`, `HMTLSIdentity.swift`, `HMTLSError.swift`: mTLS configuration and import.
- `Sources/HarborCore/Config/HConfig.swift`: global state shared by every product; `Sources/Harbor/Config/HRESTConfig.swift`: REST-only state (cache type, mocks, JSON decoder).
- `Sources/HarborJRPC/Request/HJRPCRequestManager.swift`: JSON-RPC execution and batches.
- `Sources/HarborWebSocket/Request/HWebSocketManager.swift`: handshake pipeline; `Sources/HarborWebSocket/Connection/HWebSocket.swift`: the connection actor; `HWebSocketTaskDelegate.swift`: task delegate.
