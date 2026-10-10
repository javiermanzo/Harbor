---
name: harbor
description: Use when writing, reviewing or debugging Swift code that uses the Harbor networking library (import Harbor / HarborJRPC). Covers REST requests (HGetRequestProtocol, HPostRequestProtocol, HPutRequestProtocol, HPatchRequestProtocol, HDeleteRequestProtocol), JSON-RPC 2.0, caching, auth providers and token refresh, HRetryPolicy, SSL pinning, mTLS, mocks and tests, multipart, streaming and debug logging. For upgrading Harbor 3 code use harbor-migration-v3-to-v4; for changing Harbor's own source see AGENTS.md.
---

# Harbor

Harbor is a protocol-oriented networking library for Swift 6 (strict concurrency, `async/await`). Requests are `Sendable` structs conforming to a per-method protocol. Global configuration lives on the `Harbor` enum, isolated to the global actor `@HRequestManagerActor`.

Requirements: Swift 6.0 toolchain, iOS 15+ / macOS 14+. Products: `Harbor` and `HarborJRPC` (JSON-RPC).

## Core rules

1. **Requests are structs.** Conform to `HGetRequestProtocol`, `HPostRequestProtocol`, `HPutRequestProtocol`, `HPatchRequestProtocol` or `HDeleteRequestProtocol`. Every requirement is get-only: implement it as a `let` constant or a computed property. A computed `bodyParameters: [String: Any]?` keeps the struct `Sendable` without `@unchecked`.
2. **Provide only what you need.** `url` is required (plus `Model` for GET and `bodyParameters` for POST/PUT/PATCH; return `nil` from it when you send `rawBody` or `multipartBody`). Everything else has a default: `needsAuth` (`false`), `retryPolicy`, `pathParameters`, `headerParameters`, `queryParameters`, `cacheType`, `timeoutInterval`, `multipartBody` and `rawBody` (all `nil`). Full table: `protocols.md`.
3. **REST requests never throw.** GET `request()` returns `HResponseWithResult<Model>` (`.success(Model)` / `.error(HRequestError)`). POST, PUT, PATCH and DELETE return `HResponse` (`.success` / `.error`).
4. **JSON-RPC requests throw.** `HJRPCRequestProtocol.request()` is `async throws -> Model`; `requestResult()` returns `HJRPCResponse<Model>` instead.
5. **Await configuration.** Call `await Harbor.setX(...)` from any context, then hop to `@MainActor` before touching UI.
6. **No completion handlers.** Use `async/await`. Cancel a request by cancelling its `Task` (it finishes with `.cancelled`).

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
- A POST/PUT/PATCH that must decode a response also conforms to `HRequestWithResultProtocol`, and the call site annotates the result type (`protocols.md`).
- `retryPolicy` retries transient failures only. POST and PATCH (and every JSON-RPC call) are retried after pre-connection failures only, unless `retryNonIdempotentRequests: true`.
- `request()` on a GET always contacts the server. For cache-first behavior call `cache()` or use `requestStream(source:)`, which yields at most one `.cache` and one `.remote` element (`cache.md`).
- Cached `needsAuth` responses are namespaced per credential and never deleted automatically: call `await Harbor.clearAllCache()` on logout.
- A custom `URLSession` is used as-is: SSL pinning, mTLS and redirect credential stripping apply only when it uses the delegate from `Harbor.makeURLSessionDelegate()`, created after configuring pins and mTLS (`security.md`).
- Pins must be `base64(SHA256(SPKI))`. Pin mismatches, mTLS rejections and certificate-specific `URLError`s are `HRequestError.certificate` and are never retried.
- Mocks (`HMock`, `HMockSequence`) are on in DEBUG and off in release; `await Harbor.setMocksEnabled(true)` enables them in release. They can't target JSON-RPC requests (`testing.md`).
- Logging is on in DEBUG, off in release (`setLoggingEnabled(_:)`), is opt-in per request through `HDebugRequestProtocol`, and redacts sensitive values by default (`security.md`).
- Integers beyond `Int` in JSON-RPC results decode as `HJSONValue.decimal`; digits are exact on iOS 18 / macOS 15 and later only (`examples/jrpc.md`).

## Where to look

| Need | Read |
|---|---|
| Every request protocol, property, default, response and error type; `HRetryPolicy` | `protocols.md` |
| Request flow, actor model, URLSession management, connectivity | `architecture.md` |
| Cache types, HTTP caching semantics, keys, offline behavior, streaming | `cache.md` |
| SSL pinning, mTLS, redirects, custom sessions, auth provider and 401 flow, log redaction | `security.md` |
| Mocks, `HMockSequence`, XCTest patterns, stubbing the network | `testing.md` |
| Copy-ready code: everyday requests, global configuration | `examples/basic.md` |
| Copy-ready code: multipart, streaming, OAuth2, pagination, cancellation | `examples/advanced.md` |
| JSON-RPC: setup, batches, notifications, errors | `examples/jrpc.md` |
| Upgrading from Harbor 3 | `../harbor-migration-v3-to-v4/SKILL.md` |
