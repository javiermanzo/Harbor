# Harbor Authentication

One auth provider, set with `Harbor.setAuthProvider(_:)`, signs every request that sets `needsAuth = true`: REST requests, JSON-RPC calls and WebSocket handshakes. `HAuthProviderProtocol` (which inherits `Sendable`) and `HAuthorizationHeader` live in HarborCore, so any product's import brings them.

## The provider

```swift
actor TokenStore {
    private(set) var accessToken: String?
    func update(_ token: String?) { accessToken = token }
}

final class OAuthProvider: HAuthProviderProtocol {
    let store: TokenStore

    init(store: TokenStore) {
        self.store = store
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        guard let token = await store.accessToken else { return nil }   // nil: send without credentials
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        // Refresh the token (or log out). Called at most once per request; concurrent
        // requests rejected with the same header share one call. Not called when
        // getAuthorizationHeader() already returns a header different from the rejected one.
        await store.update("refreshed-token")
    }
}

struct AccountRequest: HGetRequestProtocol {
    typealias Model = String
    let url = "https://api.example.com/account"
    let needsAuth = true
}

// The request and `clearAllCache()` below are REST (`import Harbor`); a WebSocket-only app sets
// the provider the same way and closes its sockets on logout instead.
func authFlow() async {
    let store = TokenStore()
    await Harbor.setAuthProvider(OAuthProvider(store: store))
    _ = await AccountRequest().request()

    // Logout
    await store.update(nil)
    await Harbor.setAuthProvider(nil)
    await Harbor.clearAllCache()   // REST cache entries are per credential but are not deleted automatically
}
```

`getAuthorizationHeader()` returns the current header only; keep the refresh inside `authFailed()`. A provider that sends its token as a WebSocket subprotocol instead of a header doesn't fit this protocol: set `subprotocols` on the WebSocket request (it is redacted in logs and stripped on cross-origin redirects).

## Flow

- A request with `needsAuth == false` never consults the provider. With `needsAuth == true` and no provider, it fails with `.authProviderNeeded`.
- The header is applied to the built `URLRequest` last, over default and request headers. Your request value is never mutated.
- On a `401`, Harbor asks the provider for its current header (while handling the `401`, `getAuthorizationHeader()` is called at most twice: once to detect a rotated header and, only after `authFailed()`, once more for the refreshed one). If it already differs from the rejected one (a refresh finished meanwhile), the request is re-sent with it without calling `authFailed()`. Otherwise Harbor calls `authFailed()` exactly once per request (concurrent requests rejected with the same header share one call), fetches the header again, and re-sends the request once if it changed.
- When no re-send is possible, or the re-sent request is rejected again, the error is `.authNeeded`. A request that ends in `.authNeeded` after a `401` has always triggered `authFailed()`, and never more than once.
- A `401` on a request that doesn't need auth is `.authNeeded` without calling the provider; the response body is not returned (with JSON-RPC, neither is a JSON-RPC error object in it).
- A request whose task is cancelled while it waits for `authFailed()` stops waiting at once and fails with `.cancelled`; the refresh keeps running for the other requests sharing it.
- Replacing the provider (`Harbor.setAuthProvider(_:)`, e.g. on logout) while a refresh is in flight makes the waiting requests fail with `.authNeeded`: they are never re-sent with a header from the removed provider.
- These extra attempts are separate from `retryPolicy.maxRetries`: the worst case is `1 + maxRetries + 1` attempts.

## Per product

| Product | How auth applies |
|---|---|
| REST (`harbor`) | `needsAuth` on the request. `.custom` cache entries are namespaced by a hash of the credential; call `await Harbor.clearAllCache()` on logout (`../harbor/cache.md`). |
| JSON-RPC (`harbor-jrpc`) | `needsAuth` on the call. A batch is authenticated when any of its requests has `needsAuth`. Errors: `HJRPCRequestError.authNeeded` / `.authProviderNeeded`. |
| WebSocket (`harbor-websocket`) | `needsAuth` on the socket request: the handshake carries the header and gets the same `401` flow. An open connection is never re-authenticated; reconnect after a token change. Errors: `HWebSocketError.authNeeded` / `.authProviderNeeded`. |

Testing the refresh with mocks: `../harbor/testing.md` (Auth refresh).

## Related files

- `Sources/HarborCore/Auth/HAuthProviderProtocol.swift`.
- `Sources/HarborCore/Request/HRequestManager+Auth.swift`: header lookup and coalesced refresh.
- `Sources/HarborCore/Request/HRequestManager+AttemptLoop.swift`: the `401` re-send, shared by REST and WebSocket.
