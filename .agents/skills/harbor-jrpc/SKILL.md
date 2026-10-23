---
name: harbor-jrpc
description: Use when writing, reviewing or debugging Swift code that makes JSON-RPC 2.0 calls with Harbor (import HarborJRPC) - HJRPCRequestProtocol, HarborJRPC.configure, HarborJRPC.batch, notifications (notify), HJRPCParams, HJRPCId, HJSONValue, HJRPCResponse, HJRPCBatchResponse, HJRPCRequestError, HJRPCError, HJRPCStandardCode, for example Ethereum or Bitcoin node RPC. For auth, pinning, mTLS, retry policy and logging see harbor-core; for REST requests see harbor.
---

# HarborJRPC (JSON-RPC 2.0)

`HarborJRPC` sends JSON-RPC 2.0 calls (single, notification, batch) as HTTP `POST`s through Harbor's REST pipeline, so they get the auth provider, retry policy, SSL pinning, mTLS, custom session and opt-in logging. `import HarborJRPC` also brings `Harbor` (and its shared configuration in the `harbor-core` skill).

## Core rules

1. **Configure the endpoint once.** `await HarborJRPC.configure(url:jrpcVersion:)` (`jrpcVersion` defaults to `"2.0"`). A request can target another endpoint with `endpoint: URL?`.
2. **Requests are structs.** Conform to `HJRPCRequestProtocol` with `Model` (decoded from `result`) and `method`. Everything else has a default: `parameters` (`HJRPCParams?`, `.positioned([...])` or `.named([...])`), `needsAuth`, `retryPolicy`, `headerParameters`, `timeoutInterval`, `isNotification`, `requestID` and `endpoint`.
3. **Calls throw.** `request()` is `async throws -> Model` (throws `HJRPCRequestError`, which is `Equatable`); `requestResult()` returns `HJRPCResponse<Model>` instead. Notifications use `notify()` (`request()` on a notification fails with `.invalidRequest` without sending it), batches `HarborJRPC.batch(_:)`, both `async throws`.
4. **Every call is a POST.** A plain `HRetryPolicy(maxRetries:)` retries only failures that happened before the request reached the server. Opt in with `retryNonIdempotentRequests: true` for read-only methods.

```swift
import HarborJRPC

struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_getBalance"
    let parameters: HJRPCParams?
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, retryNonIdempotentRequests: true)   // read-only

    init(address: String) {
        parameters = .positioned([address, "latest"])
    }
}

func balance() async {
    await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!)
    do {
        let wei = try await GetBalanceRequest(address: "0xabc").request()
        print(wei)
    } catch let error as HJRPCRequestError {
        print(error.localizedDescription)
    } catch {
        print(error)
    }
}
```

## Gotchas

- A response `id` that doesn't match the request's fails with `.idMismatch`. Ids are generated (UUID strings) unless you set `requestID`.
- The `jsonrpc` member of a response must equal the configured version, otherwise `.invalidResponse` (notifications don't check it).
- 4xx/5xx responses whose body is a JSON-RPC error object surface as `.jrpcError` (`HJRPCError.httpStatusCode` is set), not `.api`. A `401` is the exception: it goes through the auth flow and ends in `.authNeeded`, without the error object.
- `result: null` decodes when `Model` is optional (`typealias Model = Transaction?`).
- Integers beyond `Int` decode as `HJSONValue.decimal`; digits are exact on iOS 18 / macOS 15 and later only. Parameters JSON can't represent (`Double.nan`) fail with `.codable`.
- `HarborJRPC.batch(_:)` returns one element per request that is not a notification, in request order (matched by `id`, whatever order the server answers in), then any element whose `id` matches no request. Ids must be unique: two requests with the same `requestID` throw `.malformedRequest`. All requests must share an endpoint; headers, auth, retry policy, timeout and debug settings are merged (`examples.md`). An empty batch returns `[]` without a network call.
- `HMock` can't target JSON-RPC calls: stub the transport with a `URLProtocol` on a custom session and set a fixed `requestID` (`examples.md`, Testing).
- Debug logs name the app's request type and method (`BlockNumberRequest (eth_blockNumber)`).

## Where to look

| Need | Read |
|---|---|
| Requirements table, Ethereum/Bitcoin examples, `HJSONValue`, notifications, batches, errors, SwiftUI polling, testing | `examples.md` |
| Auth provider and `401` refresh, pinning, mTLS, custom `URLSession`, `HRetryPolicy`, logging | `../harbor-core/SKILL.md` |
| `URLProtocol` stubs on a custom session | `../harbor/testing.md` |
| Upgrading Harbor 3 JSON-RPC code | `../harbor-migration-v3-to-v4/SKILL.md` (section 12) |
