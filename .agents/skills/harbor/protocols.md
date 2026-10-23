# Harbor Protocols

Reference for every public REST request protocol, its requirements and defaults, and the response types. All requirements are get-only, so implement them with `let` constants or computed properties. `HRetryPolicy` and `HDebugRequestProtocol` are shared by every product: `../harbor-core/retry.md` and `../harbor-core/logging.md`.

## `HRequestBaseRequestProtocol` (`Sendable`)

| Property | Type | Default | Notes |
|---|---|---|---|
| `url` | `String` | required | `http` or `https` only. May contain `{name}` placeholders for `pathParameters`. |
| `httpMethod` | `HHttpMethod` | set by the method protocol | `.get`, `.post`, `.put`, `.patch`, `.delete`. |
| `needsAuth` | `Bool` | `false` | Adds the auth provider's header (`../harbor-core/auth.md`). |
| `retryPolicy` | `HRetryPolicy?` | `nil` | `nil` means no retries (`../harbor-core/retry.md`). |
| `pathParameters` | `[String: String]?` | `nil` | Values are percent-encoded, including `/` (`%2F`). A `..` segment fails with `.malformedRequest`. |
| `headerParameters` | `[String: String]?` | `nil` | Merged over `Harbor.setDefaultHeaderParameters` (names compared case-insensitively). The auth header is applied last. |
| `timeoutInterval` | `TimeInterval?` | `nil` | Set on the `URLRequest`. `nil` uses `Harbor.setDefaultTimeoutInterval` (15 s). |

## `HRequestWithResultProtocol`

```text
associatedtype Model: HModel                       // HModel = Codable & Sendable
func parseData<T: Codable>(data: Data, model: T.Type) throws -> T   // default: JSONDecoder
func request() async -> HResponseWithResult<Model>
```

Override `parseData` for custom decoding (date strategies, envelopes). The same function decodes cached bodies, off Harbor's actor.

## `HRequestWithEmptyResponseProtocol`

`func request() async -> HResponse`. Any 2xx response is `.success`, and the body is ignored. A `304 Not Modified` answering your own conditional headers is `.success` too.

## `HRequestWithBodyProtocol` (POST / PUT / PATCH)

| Property | Type | Default | Notes |
|---|---|---|---|
| `bodyParameters` | `[String: Any]?` | required | Serialized with `JSONSerialization`. Values JSON can't represent (`Date`, `Data`, NaN, custom types) fail with `.malformedRequest`. Implement it as a computed property so the struct stays `Sendable`; return `nil` when another body is sent. |
| `multipartBody` | `[String: HFormValue]?` | `nil` | Sent as `multipart/form-data`; takes precedence over `bodyParameters`. The only way to send multipart. A body with files is streamed from a temporary file. |
| `rawBody` | `Data?` | `nil` | Takes precedence over everything. Sent as-is. |

The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters`; a request with none of them is sent without a body. `rawBody` and `bodyParameters` are sent with `Content-Type: application/json` unless the default headers or `headerParameters` set a `Content-Type` (header names match case-insensitively, so `content-type` also replaces it). A multipart body always sets its own `Content-Type` with the boundary.

## Method protocols

| Protocol | Inherits | Extra | `request()` returns |
|---|---|---|---|
| `HGetRequestProtocol` | `HRequestWithResultProtocol` | `queryParameters: [String: String]?`, `cacheType: HCache.CacheType?`, `shouldCache(statusCode:)` (default `true`; return `false` for a success status that is not the resource yet, such as `202 Accepted`), `cache()`, `cachedETag()`, `clearCache()`, `requestStream(source:)` | `HResponseWithResult<Model>` |
| `HPostRequestProtocol` | `HRequestWithBodyProtocol` | | `HResponse` |
| `HPutRequestProtocol` | `HRequestWithBodyProtocol` | | `HResponse` |
| `HPatchRequestProtocol` | `HRequestWithBodyProtocol` | | `HResponse` |
| `HDeleteRequestProtocol` | `HRequestWithEmptyResponseProtocol` | | `HResponse` |

Query parameters are strictly percent-encoded (only unreserved characters stay literal, so `+` becomes `%2B`). They are merged with any query in `url` and sorted by name.

Copy-ready request declarations for every method: `examples/basic.md`.

### Body requests that return a model

The body protocols return `HResponse`. To decode a response body, also conform to `HRequestWithResultProtocol` (`HPostRequestProtocol, HRequestWithResultProtocol`, with a `Model`) and annotate the result type at the call site to choose the overload: `let response: HResponseWithResult<User> = await request.request()`. Example: `examples/basic.md`.

### Multipart

`.text(String)` values may contain line breaks: a value is the part's body. `.file(url:mimeType:fileName:)`: if `mimeType` is `nil`, no part `Content-Type` is sent. If `fileName` is `nil`, the URL's last path component is used. Field and file names containing CR/LF or a double quote, and values or files containing the boundary, fail with `.malformedRequest`. Cancelling the request stops the copy of a large file. Example: `examples/advanced.md`.

## Responses and errors

```swift
struct Article: Codable, Sendable {
    let title: String
}

func handle(_ response: HResponseWithResult<Article>) {
    switch response {
    case .success(let article):
        print(article.title)
    case .error(let error):
        switch error {
        case .api(let statusCode, let data):
            print("HTTP \(statusCode), \(data.count) bytes")
        case .codable(let modelName, let underlying):
            print("Cannot decode \(modelName): \(underlying)")
        case .noConnection, .timeout, .cannotFindHost, .cannotConnectToHost:
            print("Network problem")
        case .networkFailure(let urlError):
            print("URLError \(urlError.code)")
        case .certificate:
            print("TLS / pinning failure")
        case .authNeeded, .authProviderNeeded:
            print("Login required")
        case .malformedRequest(let reason):
            print("Bad request: \(reason ?? "-")")
        case .cancelled:
            break
        case .invalidHttpResponse, .noCachedDataFound, .unknown:
            print(error.localizedDescription)
        }
    }
}

func handle(_ response: HResponse) {
    if case .error(let error) = response, error == .noConnection {
        print("Offline")
    }
}
```

`HRequestError` cases: `.api(statusCode:data:)`, `.invalidHttpResponse`, `.authProviderNeeded`, `.authNeeded`, `.codable(modelName:error:)`, `.noConnection`, `.malformedRequest(reason:)`, `.timeout`, `.cannotFindHost`, `.cannotConnectToHost`, `.cancelled`, `.certificate`, `.noCachedDataFound` (only from `requestStream(source: .cacheOnly)`), `.networkFailure(URLError)` and `.unknown(Error)`. It conforms to `Error`, `Sendable`, `LocalizedError` and `Equatable`. Payload cases compare by payload. The wrapped errors of `.codable` and `.unknown` compare by type, domain, code and description, and `.networkFailure` compares by `URLError` code. `.api` descriptions include a redacted body preview.

Notes on the mapping:

- `.noConnection` covers an offline device and a connection that dropped while the request was in flight (`URLError.networkConnectionLost`): in the second case the request may have reached the server.
- Any `401` ends in `.authNeeded` once the auth flow gives up, including a `401` on a request without `needsAuth` (the provider is not consulted, and the response body is not returned).
- A `304` answering validators you set yourself is `.api(statusCode: 304, data:)` for a GET (`cache.md`).

## Related files

- `Sources/Harbor/Request/`: one file per protocol (`HRequestBaseRequestProtocol.swift`, `HRequestWithResultProtocol.swift`, `HRequestWithEmptyResponseProtocol.swift`, `HRequestWithBodyProtocol.swift`, `HGetRequestProtocol.swift`, `HPostRequestProtocol.swift`, ...), plus `HResponse.swift`, `HResponseWithResult.swift`, `HFormValue.swift` and `HRequestSource.swift`.
- `Sources/HarborCore/Request/HRequestError.swift` and `HRetryPolicy.swift` (shared with the other products).
- `Sources/Harbor/Cache/HGetRequestProtocol+Cache.swift`: `cache()`, `cachedETag()`, `clearCache()`.
