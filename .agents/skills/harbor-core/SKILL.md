---
name: harbor-core
description: Use when configuring what every Harbor product shares (Harbor REST, HarborJRPC, HarborWebSocket) - the auth provider and 401 token refresh (HAuthProviderProtocol, Harbor.setAuthProvider), SSL pinning (setSSLPinningKeys, computePin), mTLS (HMTLS, HMTLSError), a custom URLSession (makeURLSessionDelegate, HURLSessionDelegate), cross-origin redirects, HRetryPolicy and backoff, default timeouts and headers, cookies, connectivity, or debug logging and redaction (HDebugRequestProtocol, setLoggingEnabled, updateLogSensitiveKeys). Also when changing Harbor's internals (architecture).
---

# Harbor Core (shared configuration)

`HarborCore` is the module every Harbor product is built on: authentication and token refresh, SSL pinning, mTLS, redirects, the `URLSession` pool, `HRetryPolicy`, logging and redaction, and the `Harbor.setX(_:)` configuration. It is not a product: `import Harbor`, `import HarborJRPC` and `import HarborWebSocket` re-export it, so everything here is available with any of them.

Requirements: Swift 6.0 toolchain, iOS 15+ / macOS 14+.

## Rules

1. **Configuration is global and shared.** A `Harbor.setX(...)` call applies to every product at once: the auth provider set for REST requests also signs JSON-RPC calls and WebSocket handshakes.
2. **Await every setter.** `Harbor` is isolated to the global actor `@HRequestManagerActor`: call `await Harbor.setX(...)` from any context, then hop to `@MainActor` before touching UI. Settings are functions, not settable properties.
3. **Configure security before building a custom session.** `Harbor.makeURLSessionDelegate()` captures the pins and mTLS identity configured at that moment: build a new delegate and session after changing them.
4. **Keep the safe defaults.** Logs are redacted, credentials are stripped on cross-origin redirects, and certificate failures are never retried. Use `setLogSensitiveValues(true)` for local debugging only.

## Global configuration

```swift
final class TokenProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer token")
    }

    func authFailed() async {}
}

func configureHarbor() async {
    await Harbor.setDefaultTimeoutInterval(30)                // idle timeout per request (default 15 s)
    await Harbor.setDefaultResourceTimeoutInterval(300)       // whole-transfer limit of Harbor-built sessions (default: system, 7 days)
    await Harbor.setDefaultHeaderParameters(["Accept": "application/json"])   // request headers override them
    await Harbor.setHTTPShouldHandleCookies(true)             // default false
    await Harbor.setAuthProvider(TokenProvider())             // auth.md
    await Harbor.setSSLPinningKeys(["API_PIN_BASE64="], forHosts: ["api.example.com"])   // security.md
    await Harbor.setLoggingEnabled(true)                      // default: on in DEBUG, off in release (logging.md)
}
```

What each product does with the shared settings:

| Setting | REST (`Harbor`) | JSON-RPC (`HarborJRPC`) | WebSocket (`HarborWebSocket`) |
|---|---|---|---|
| `setAuthProvider(_:)` | `needsAuth` requests | `needsAuth` calls | `needsAuth` handshakes |
| `setDefaultTimeoutInterval(_:)` | every request | every call | the handshake |
| `setDefaultResourceTimeoutInterval(_:)` | Harbor-built sessions | Harbor-built sessions | not applied (a connection may outlive any transfer) |
| `setDefaultHeaderParameters(_:)`, `setHTTPShouldHandleCookies(_:)` | every request | every call | the handshake |
| SSL pinning, mTLS, redirect stripping | every request | every call | the handshake |
| `setCustomURLSession(_:)` | used as-is | used as-is | used as-is |
| `setLoggingEnabled(_:)` | `HDebugRequestProtocol` requests | `HDebugRequestProtocol` calls | `HDebugRequestProtocol` sockets |
| `setAssumeNetworkAvailableInDebug(_:)` | connectivity check | connectivity check | connectivity check |

Product-specific settings live with their product: the default cache type, mocks and `Harbor.clearAllCache()` (`harbor` skill), `HarborJRPC.configure(url:jrpcVersion:)` (`harbor-jrpc`) and `HarborWebSocket.setDefaultPingInterval(_:)` (`harbor-websocket`).

## Gotchas

- With `needsAuth == true` and no provider, a request fails with `.authProviderNeeded`. A `401` triggers at most one `authFailed()` per request, and concurrent rejections share it (`auth.md`).
- Pins must be `base64(SHA256(SPKI))`. Pin mismatches, mTLS rejections and certificate-specific `URLError`s are reported as `.certificate` and are never retried (`security.md`).
- A custom `URLSession` is used as-is: pinning, mTLS and redirect stripping apply only when its delegate is `Harbor.makeURLSessionDelegate()` (or forwards to one).
- `HRetryPolicy` retries transient failures only. Non-idempotent requests (POST, PATCH, every JSON-RPC call) are retried only after failures that happened before the request reached the server, unless `retryNonIdempotentRequests: true` (`retry.md`).
- DEBUG builds skip the connectivity check (requests are always attempted) unless `Harbor.setAssumeNetworkAvailableInDebug(false)` is set.
- Debug output is opt-in per request (`HDebugRequestProtocol`), needs logging enabled and redacts sensitive values. Security warnings are logged even with logging disabled (`logging.md`).

## Where to look

| Need | Read |
|---|---|
| Auth provider, token refresh, the `401` flow, logout | `auth.md` |
| SSL pinning, mTLS, redirects, custom `URLSession` | `security.md` |
| `HRetryPolicy`: what is retried, backoff, `Retry-After` | `retry.md` |
| Debug logging, `HDebugRequestProtocol`, log redaction | `logging.md` |
| Internals: modules, actor model, request and handshake flows, session pool | `architecture.md` |
| REST requests, cache, mocks | `../harbor/SKILL.md` |
| JSON-RPC 2.0 | `../harbor-jrpc/SKILL.md` |
| WebSocket | `../harbor-websocket/SKILL.md` |
| Upgrading from Harbor 3 | `../harbor-migration-v3-to-v4/SKILL.md` |
