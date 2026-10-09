# Harbor Architecture

How a request moves through Harbor, and where each concern lives in `Sources/`.

## Modules

| Module | Purpose | Key files |
|---|---|---|
| `Harbor` | REST requests, cache, auth, retry, security, mocks, logging | `Harbor.swift`, `Request/`, `Cache/`, `Config/`, `Debug/`, `Mock/`, `Auth/`, `Utils/` |
| `HarborJRPC` | JSON-RPC 2.0 on top of Harbor | `HarborJRPC.swift`, `Request/`, `Config/` |

Harbor depends on [LogBird](https://github.com/javiermanzo/LogBird) (`from: "2.1.0"`) for logging, behind the internal `HLogger` facade.

## Protocol hierarchy

```text
HRequestBaseRequestProtocol            url, httpMethod, needsAuth, retryPolicy,
│                                      pathParameters, headerParameters, timeoutInterval
├── HRequestWithResultProtocol         associatedtype Model: HModel; parseData; request() -> HResponseWithResult<Model>
│   └── HGetRequestProtocol            queryParameters, cacheType, cache(), requestStream(source:)
└── HRequestWithEmptyResponseProtocol  request() -> HResponse
    ├── HRequestWithBodyProtocol       bodyParameters, multipartBody, rawBody (first non-nil of rawBody, multipartBody, bodyParameters)
    │   ├── HPostRequestProtocol
    │   ├── HPutRequestProtocol
    │   └── HPatchRequestProtocol
    └── HDeleteRequestProtocol

HDebugRequestProtocol                  debugType (opt-in logging, combine with any request)
HAuthProviderProtocol                  getAuthorizationHeader(), authFailed()
HJRPCRequestProtocol (HarborJRPC)      method, parameters, request() async throws -> Model
```

`HModel` is `Codable & Sendable`. All requirements are get-only, and protocol extensions supply the defaults (see `protocols.md`).

## Concurrency model

- `@globalActor public actor HRequestManagerActor` serializes all of Harbor's mutable state.
- `public enum Harbor` (the configuration API) and the internal `HRequestManager`, `HConfig` (`HConfig.shared`), `HMocker` and `HarborJRPC` are isolated to that actor. That's why every `Harbor.setX(...)` call needs `await` from outside the actor.
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
 │       else fail with .noConnection (needsAuth: the credential remembered from the last
 │       online success for that URL is used without asking the provider; when nothing is
 │       remembered the provider is asked for its current header; the un-namespaced entry
 │       is never served)
 ├─ needsAuth? → authProvider.getAuthorizationHeader()  (no provider → .authProviderNeeded)
 └─ attempt loop (runAttempts)
      ├─ HURLBuilder.prepareRequest: URL + path/query encoding, timeout, cookies, body,
      │  default headers → request headers → auth header, conditional validators (custom cache)
      ├─ URLSession data/upload task with a per-task HTaskContext delegate
      ├─ 2xx  → decode off-actor, store in cache (GET; needsAuth: only under the credential it
      │         was sent with, never when sent without one; skipped if the request started
      │         before clearAllCache() / setAuthProvider(_:)) → .success
      ├─ 304  → serve + refresh the cached entry; if no cached body and Harbor injected the
      │         validators: re-send once without them (caller-set validators: .api(304))
      ├─ 401  → provider already rotated the header? retry with it without authFailed();
      │         else authFailed() (once per request, coalesced across concurrent requests)
      │         → retry once if the provider returns a different header, else .authNeeded.
      │         A request that ends in .authNeeded after a 401 has always triggered authFailed()
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

## JSON-RPC adapter

`HJRPCRequestProtocol` requests are wrapped in an internal `HPostRequestProtocol & HRequestWithResultProtocol` struct whose `rawBody` is the encoded JSON-RPC envelope (`jsonrpc`, `method`, `id`, `params`). They go through the same pipeline: auth, retry, logging (when the JSON-RPC request conforms to `HDebugRequestProtocol`) and transport security. Batches use another internal wrapper. See `examples/jrpc.md`.

## Related files

- `Sources/Harbor/Request/HRequestManager.swift`: attempt loop, auth refresh, session cache.
- `Sources/Harbor/Request/HRequestProtocol.swift`: protocols, defaults, streaming.
- `Sources/Harbor/Request/HRetryPolicy.swift`: retry classification.
- `Sources/Harbor/Utils/HURLBuilder.swift`: URL, header and body construction.
- `Sources/Harbor/Request/HURLSessionDelegate.swift`: pinning, mTLS, redirects.
- `Sources/Harbor/Config/HConfig.swift`: global state.
- `Sources/HarborJRPC/Request/HJRPCRequestManager.swift`: JSON-RPC execution and batches.
