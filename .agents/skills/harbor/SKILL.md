---
name: harbor
description: Use when writing, reviewing or debugging Swift code that sends REST requests with the Harbor networking library (import Harbor) - HGetRequestProtocol, HPostRequestProtocol, HPutRequestProtocol, HPatchRequestProtocol, HDeleteRequestProtocol, HResponse, HResponseWithResult, HRequestError, caching (HCache, cache(), requestStream), multipart (HFormValue), rawBody, mocks (HMock, HMockSequence) and XCTest. For JSON-RPC use harbor-jrpc, for WebSocket harbor-websocket, for auth, pinning, mTLS, retry policy and logging harbor-core, for upgrading Harbor 3 code harbor-migration-v3-to-v4.
---

# Harbor (REST)

Harbor is a protocol-oriented networking library for Swift 6 (strict concurrency, `async/await`). A REST request is a `Sendable` struct conforming to one protocol per HTTP method. Global configuration lives on the `Harbor` enum, isolated to the global actor `@HRequestManagerActor`.

Requirements: Swift 6.0 toolchain, iOS 15+ / macOS 14+. `import Harbor` also brings the shared configuration (auth, pinning, mTLS, retry policy, logging) documented in the `harbor-core` skill.

## Core rules

1. **Requests are structs.** Conform to `HGetRequestProtocol`, `HPostRequestProtocol`, `HPutRequestProtocol`, `HPatchRequestProtocol` or `HDeleteRequestProtocol`. Every requirement is get-only: implement it as a `let` constant or a computed property. A computed `bodyParameters: [String: Any]?` keeps the struct `Sendable` without `@unchecked`.
2. **Provide only what you need.** `url` is required (plus `Model` for GET and `bodyParameters` for POST/PUT/PATCH; return `nil` from it when you send `rawBody` or `multipartBody`). Everything else has a default: `needsAuth` (`false`), `retryPolicy`, `pathParameters`, `headerParameters`, `queryParameters`, `cacheType`, `timeoutInterval`, `multipartBody` and `rawBody` (all `nil`). Full table: `protocols.md`.
3. **Requests never throw.** GET `request()` returns `HResponseWithResult<Model>` (`.success(Model)` / `.error(HRequestError)`). POST, PUT, PATCH and DELETE return `HResponse` (`.success` / `.error`).
4. **Await configuration.** Call `await Harbor.setX(...)` from any context, then hop to `@MainActor` before touching UI.
5. **No completion handlers.** Use `async/await`. Cancel a request by cancelling its `Task` (it finishes with `.cancelled`).

```swift
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users/{id}"
    let pathParameters: [String: String]?

    init(id: Int) {
        pathParameters = ["id": String(id)]
    }
}

struct CreateUserRequest: HPostRequestProtocol {
    let url = "https://api.example.com/users"
    let name: String

    var bodyParameters: [String: Any]? { ["name": name] }
}

func load() async {
    switch await GetUserRequest(id: 1).request() {
    case .success(let user):
        print(user.name)
    case .error(let error):
        print(error.localizedDescription)
    }

    if case .error(let error) = await CreateUserRequest(name: "Jane").request() {
        print(error)
    }
}
```

## Gotchas

- The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters` (JSON). A body JSON can't encode fails with `.malformedRequest`.
- Any `401` ends in `.authNeeded` once the auth flow gives up, also on a request without `needsAuth`, and its body is not returned: a login endpoint answering wrong credentials with `401` reports `.authNeeded` (`../harbor-core/auth.md`).
- A POST/PUT/PATCH that must decode a response also conforms to `HRequestWithResultProtocol`, and the call site annotates the result type (`protocols.md`).
- Only `http` and `https` URLs are accepted; anything else fails with `.malformedRequest`.
- With the `.custom` cache, `request()` on a GET always contacts the server (conditionally when it can); with the default `.urlCache()`, `URLSession` may answer from `URLCache`. For cache-first behavior call `cache()` or use `requestStream(source:)`, which yields at most one `.cache` and one `.remote` element (`cache.md`).
- Cached `.custom` responses are namespaced per credential (the provider's header, or sensitive headers such as `Authorization`/`X-API-Key` in `headerParameters` and default headers; `.urlCache` is not) and never deleted automatically: call `await Harbor.clearAllCache()` on logout.
- `retryPolicy` retries transient failures only; POST and PATCH only after pre-connection failures unless `retryNonIdempotentRequests: true` (`../harbor-core/retry.md`).
- Mocks (`HMock`, `HMockSequence`) are on in DEBUG and off in release; `await Harbor.setMocksEnabled(true)` enables them in release. They apply to REST requests only (`testing.md`).
- Logging is opt-in per request through `HDebugRequestProtocol` and redacts sensitive values (`../harbor-core/logging.md`).

## Where to look

| Need | Read |
|---|---|
| Every request protocol, property, default, response and `HRequestError` case | `protocols.md` |
| Cache types, HTTP caching semantics, keys, offline behavior, streaming | `cache.md` |
| Mocks, `HMockSequence`, XCTest patterns, stubbing the network | `testing.md` |
| Copy-ready code: everyday requests, headers, global configuration | `examples/basic.md` |
| Copy-ready code: multipart, streaming, OAuth2, pagination, cancellation | `examples/advanced.md` |
| Auth provider and `401` refresh, pinning, mTLS, custom `URLSession`, `HRetryPolicy`, logging | `../harbor-core/SKILL.md` |
| JSON-RPC 2.0 (`HarborJRPC`) | `../harbor-jrpc/SKILL.md` |
| WebSocket (`HarborWebSocket`) | `../harbor-websocket/SKILL.md` |
| Upgrading from Harbor 3 | `../harbor-migration-v3-to-v4/SKILL.md` |
