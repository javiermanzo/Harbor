# Harbor Protocols

Reference for every public request protocol, its requirements and defaults, and the response types. All requirements are get-only, so implement them with `let` constants or computed properties.

## `HRequestBaseRequestProtocol` (`Sendable`)

| Property | Type | Default | Notes |
|---|---|---|---|
| `url` | `String` | required | May contain `{name}` placeholders for `pathParameters`. |
| `httpMethod` | `HHttpMethod` | set by the method protocol | `.get`, `.post`, `.put`, `.patch`, `.delete`. |
| `needsAuth` | `Bool` | `false` | Adds the auth provider's header (see `security.md`). |
| `retryPolicy` | `HRetryPolicy?` | `nil` | `nil` means no retries. |
| `pathParameters` | `[String: String]?` | `nil` | Values are percent-encoded, including `/` (`%2F`). A `..` segment fails with `.malformedRequest`. |
| `headerParameters` | `[String: String]?` | `nil` | Merged over `Harbor.setDefaultHeaderParameters`. The auth header is applied last. |
| `timeoutInterval` | `TimeInterval?` | `nil` | Set on the `URLRequest`. `nil` uses `Harbor.setDefaultTimeoutInterval` (15 s). |

## `HRequestWithResultProtocol`

```text
associatedtype Model: HModel                       // HModel = Codable & Sendable
func parseData<T: Codable>(data: Data, model: T.Type) throws -> T   // default: JSONDecoder
func request() async -> HResponseWithResult<Model>
```

Override `parseData` for custom decoding (date strategies, envelopes). The same function decodes cached bodies.

## `HRequestWithEmptyResponseProtocol`

`func request() async -> HResponse`. Any 2xx response is `.success`, and the body is ignored.

## `HRequestWithBodyProtocol` (POST / PUT / PATCH)

| Property | Type | Default | Notes |
|---|---|---|---|
| `bodyType` | `HRequestDataType` | `.json` | `.json` or `.multipart` (applies to `bodyParameters`). |
| `bodyParameters` | `[String: Any]?` | required | Serialized with `JSONSerialization`. Values JSON can't represent (`Date`, `Data`, NaN, custom types) fail with `.malformedRequest`. Implement it as a computed property so the struct stays `Sendable`. |
| `multipartBody` | `[String: HFormValue]?` | `nil` | Takes precedence over `bodyParameters`. A body with files is streamed from a temporary file. |
| `rawBody` | `Data?` | `nil` | Takes precedence over everything. Sent as-is with `Content-Type: application/json` (override it in `headerParameters`). |

## Method protocols

| Protocol | Inherits | Extra | `request()` returns |
|---|---|---|---|
| `HGetRequestProtocol` | `HRequestWithResultProtocol` | `queryParameters: [String: String]?`, `cacheType: HCache.CacheType?`, `cache()`, `cachedETag()`, `clearCache()`, `requestStream(source:)` | `HResponseWithResult<Model>` |
| `HPostRequestProtocol` | `HRequestWithBodyProtocol` | | `HResponse` |
| `HPutRequestProtocol` | `HRequestWithBodyProtocol` | | `HResponse` |
| `HPatchRequestProtocol` | `HRequestWithBodyProtocol` | | `HResponse` |
| `HDeleteRequestProtocol` | `HRequestWithEmptyResponseProtocol` | | `HResponse` |

Query parameters are strictly percent-encoded (only unreserved characters stay literal, so `+` becomes `%2B`). They are merged with any query in `url` and sorted by name.

### GET

```swift
struct Article: Codable, Sendable {
    let id: Int
    let title: String
}

struct SearchArticlesRequest: HGetRequestProtocol {
    typealias Model = [Article]
    let url = "https://api.example.com/{section}/articles"
    let pathParameters: [String: String]?
    let queryParameters: [String: String]?
    let headerParameters: [String: String]? = ["Accept-Language": "en"]
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .fiveMinutes))
    let timeoutInterval: TimeInterval? = 10

    init(section: String, query: String, page: Int) {
        pathParameters = ["section": section]
        queryParameters = ["q": query, "page": String(page)]
    }
}
```

### POST / PUT / PATCH / DELETE

```swift
struct CreateArticleRequest: HPostRequestProtocol {
    let url = "https://api.example.com/articles"
    let needsAuth = true
    let title: String
    let tags: [String]

    var bodyParameters: [String: Any]? {
        ["title": title, "tags": tags]
    }
}

struct ReplaceArticleRequest: HPutRequestProtocol {
    let url = "https://api.example.com/articles/{id}"
    let pathParameters: [String: String]?
    let rawBody: Data?

    var bodyParameters: [String: Any]? { nil }

    init(id: Int, article: Article) throws {
        pathParameters = ["id": String(id)]
        rawBody = try JSONEncoder().encode(article)
    }
}

struct RenameArticleRequest: HPatchRequestProtocol {
    let url = "https://api.example.com/articles/{id}"
    let pathParameters: [String: String]?
    let title: String

    var bodyParameters: [String: Any]? { ["title": title] }

    init(id: Int, title: String) {
        pathParameters = ["id": String(id)]
        self.title = title
    }
}

struct DeleteArticleRequest: HDeleteRequestProtocol {
    let url = "https://api.example.com/articles/{id}"
    let pathParameters: [String: String]?

    init(id: Int) {
        pathParameters = ["id": String(id)]
    }
}
```

### Body requests that return a model

The body protocols return `HResponse`. To decode a response body, also conform to `HRequestWithResultProtocol` and annotate the result type to choose the overload:

```swift
struct CreateArticleReturningRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = Article
    let url = "https://api.example.com/articles"
    let title: String

    var bodyParameters: [String: Any]? { ["title": title] }
}

func createArticle() async -> Article? {
    let response: HResponseWithResult<Article> = await CreateArticleReturningRequest(title: "Hello").request()
    if case .success(let article) = response {
        return article
    }
    return nil
}
```

### Multipart

```swift
struct UploadAvatarRequest: HPostRequestProtocol {
    let url = "https://api.example.com/me/avatar"
    let needsAuth = true
    let fileURL: URL

    var bodyParameters: [String: Any]? { nil }

    var multipartBody: [String: HFormValue]? {
        [
            "description": .text("Profile picture"),
            "avatar": .file(url: fileURL, mimeType: "image/jpeg", fileName: "avatar.jpg")
        ]
    }
}
```

`.file(url:mimeType:fileName:)`: if `mimeType` is `nil`, no part `Content-Type` is sent. If `fileName` is `nil`, the URL's last path component is used. Field names or values containing CR/LF or the boundary fail with `.malformedRequest`. `bodyType = .multipart` with `bodyParameters` also works for string-convertible values; prefer `multipartBody`.

## `HDebugRequestProtocol`

Opt-in logging per request. `debugType: HDebugRequestType` (`.none`, `.request`, `.response`, `.requestAndResponse`) defaults to `.requestAndResponse`. Output also requires `Harbor.setLoggingEnabled(true)`, which is the default in DEBUG. Every value is redacted (see `security.md`).

```swift
struct DebuggedArticleRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = Article
    let url = "https://api.example.com/articles/1"
    let debugType: HDebugRequestType = .requestAndResponse
}
```

## `HRetryPolicy`

```swift
let conservative = HRetryPolicy(maxRetries: 3)                    // 0.3s, 0.6s, 1.2s (+0...0.1s jitter)
let custom = HRetryPolicy(maxRetries: 5,
                          baseDelay: 1,
                          multiplier: 1.5,
                          jitter: 0...0.5,
                          retryableStatusCodes: [429, 503],
                          retryNonIdempotentRequests: false)
```

Retried failures:

- statuses in `retryableStatusCodes` (default `HRetryPolicy.defaultRetryableStatusCodes`: 408, 425, 429, 500, 502, 503, 504);
- `URLError` `.timedOut`, `.networkConnectionLost` and `.secureConnectionFailed` (idempotent methods, or all methods with `retryNonIdempotentRequests`);
- `URLError` `.cannotConnectToHost`, `.cannotFindHost`, `.dnsLookupFailed`, `.notConnectedToInternet`, `.internationalRoamingOff`, `.callIsActive` and `.dataNotAllowed` (any method, since the request never reached the server).

Never retried: other statuses (400, 404, 422, ...), cancellation, certificate errors (`.certificate`: pinning, mTLS and certificate-specific `URLError`s), malformed URLs, and errors other than `URLError`. GET, PUT and DELETE are idempotent. POST and PATCH need `retryNonIdempotentRequests: true` to be retried after a retryable status or an in-flight error. On a 429 or 503, `Retry-After` (delta-seconds or HTTP-date) replaces the backoff. Backoff delays are capped at `HRetryPolicy.maxDelay` (60 s); a `Retry-After` longer than that is not waited for, and the request returns `.api(429/503)` immediately. A 401 is handled by the auth flow, outside `maxRetries`.

## Responses and errors

```swift
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
        case .invalidHttpResponse, .invalidRequest, .noCachedDataFound, .unknown:
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

`HRequestError` conforms to `Error`, `Sendable`, `LocalizedError` and `Equatable`. Payload cases compare by payload. The wrapped errors of `.codable` and `.unknown` compare by type, domain, code and description, and `.networkFailure` compares by `URLError` code. `.api` descriptions include a redacted body preview.

## `HJRPCRequestProtocol` (HarborJRPC)

| Property | Type | Default |
|---|---|---|
| `Model` | `HModel` | required |
| `method` | `String` | required |
| `parameters` | `HJRPCParams?` (`.named([String: any Encodable & Sendable])` / `.positioned([any Encodable & Sendable])`) | `nil` |
| `needsAuth` | `Bool` | `false` |
| `retryPolicy` | `HRetryPolicy?` | `nil` (calls are POST, so see `retryNonIdempotentRequests`) |
| `headers` | `[String: String]?` | `nil` |
| `isNotification` | `Bool` | `false` |
| `requestID` | `HJRPCId?` | `nil` (a UUID string is generated) |
| `endpoint` | `URL?` | `nil` (uses `HarborJRPC.setURL` / `configure`) |

Methods: `request() async throws -> Model`, `requestResult() async -> HJRPCResponse<Model>` and `notify() async throws`. See `examples/jrpc.md`.

## Related files

- `Sources/Harbor/Request/HRequestProtocol.swift`, `HRetryPolicy.swift`, `HRequestError.swift`, `HResponse.swift`, `HFormValue.swift`.
- `Sources/Harbor/Debug/HDebugRequestProtocol.swift`.
- `Sources/HarborJRPC/Request/HJRPCRequestProtocol.swift`.
