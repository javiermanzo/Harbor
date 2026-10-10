# Harbor Basic Examples

Copy-ready examples for everyday use. Every snippet compiles against Harbor 4. The models below are shared by the examples.

```swift
struct User: Codable, Sendable {
    let id: Int
    let name: String
    let email: String
}

struct SearchResults: Codable, Sendable {
    let items: [User]
    let total: Int
}
```

## GET

### Minimal GET

```swift
struct GetCurrentUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/me"
}

func showCurrentUser() async {
    switch await GetCurrentUserRequest().request() {
    case .success(let user):
        print("User: \(user.name)")
    case .error(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

### Path parameters

`{name}` placeholders in `url` are replaced with percent-encoded values (`/` becomes `%2F`, and `..` is rejected).

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users/{userId}"
    let pathParameters: [String: String]?

    init(userId: Int) {
        pathParameters = ["userId": String(userId)]
    }
}
```

### Query parameters

Values are `String`s, strictly percent-encoded (`+` becomes `%2B`, a space becomes `%20`) and sorted by name.

```swift
struct SearchUsersRequest: HGetRequestProtocol {
    typealias Model = SearchResults
    let url = "https://api.example.com/users/search"
    let queryParameters: [String: String]?

    init(term: String, page: Int, limit: Int = 20) {
        queryParameters = ["q": term, "page": String(page), "limit": String(limit)]
    }
}

func search() async {
    // GET /users/search?limit=20&page=1&q=john%2Bdoe
    let response = await SearchUsersRequest(term: "john+doe", page: 1).request()
    if case .success(let results) = response {
        print(results.total)
    }
}
```

### GET with the custom cache

```swift
struct GetUserProfileRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/users/{id}/profile"
    let pathParameters: [String: String]?
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))

    init(id: Int) {
        pathParameters = ["id": String(id)]
    }
}

func profile() async -> User? {
    let request = GetUserProfileRequest(id: 123)

    // Instant: cached copy (no network), nil on a miss
    if let cached = await request.cache() {
        return cached
    }

    // Network: revalidates with ETag / Last-Modified when an entry exists and stores the response
    if case .success(let user) = await request.request() {
        return user
    }
    return nil
}
```

`request()` always contacts the server, conditionally if possible. Read `cache()` first, or use `requestStream(source: .cacheAndRemote)`, for cache-first behavior (see `../cache.md`).

## POST, PUT, PATCH, DELETE

Body requests return `HResponse` (`.success` / `.error`).

```swift
struct CreateUserRequest: HPostRequestProtocol {
    let url = "https://api.example.com/users"
    let name: String
    let email: String

    var bodyParameters: [String: Any]? {
        ["name": name, "email": email]
    }
}

func createUser() async {
    switch await CreateUserRequest(name: "John Doe", email: "john@example.com").request() {
    case .success:
        print("Created")
    case .error(let error):
        print(error)
    }
}
```

### Encodable body via `rawBody`

```swift
struct NewUser: Encodable, Sendable {
    let name: String
    let email: String
}

struct CreateUserFromModelRequest: HPostRequestProtocol {
    let url = "https://api.example.com/users"
    let rawBody: Data?

    var bodyParameters: [String: Any]? { nil }

    init(user: NewUser) throws {
        rawBody = try JSONEncoder().encode(user)
    }
}
```

The body is the first non-nil of `rawBody`, `multipartBody` and `bodyParameters`. `rawBody` is sent with `Content-Type: application/json` unless `headerParameters` sets a `Content-Type` (matched case-insensitively).

### POST that returns the created model

```swift
struct RegisterUserRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = User
    let url = "https://api.example.com/register"
    let email: String

    var bodyParameters: [String: Any]? { ["email": email] }
}

func register() async {
    // The type annotation selects the model-returning `request()`.
    let response: HResponseWithResult<User> = await RegisterUserRequest(email: "a@b.c").request()
    if case .success(let user) = response {
        print(user.id)
    }
}
```

### PUT / PATCH / DELETE

```swift
struct UpdateUserRequest: HPutRequestProtocol {
    let url = "https://api.example.com/users/{id}"
    let pathParameters: [String: String]?
    let user: User

    var bodyParameters: [String: Any]? {
        ["name": user.name, "email": user.email]
    }

    init(user: User) {
        self.user = user
        pathParameters = ["id": String(user.id)]
    }
}

struct PatchUserEmailRequest: HPatchRequestProtocol {
    let url = "https://api.example.com/users/{id}"
    let pathParameters: [String: String]?
    let email: String

    var bodyParameters: [String: Any]? { ["email": email] }

    init(id: Int, email: String) {
        pathParameters = ["id": String(id)]
        self.email = email
    }
}

struct DeleteUserRequest: HDeleteRequestProtocol {
    let url = "https://api.example.com/users/{id}"
    let pathParameters: [String: String]?
    let needsAuth = true

    init(id: Int) {
        pathParameters = ["id": String(id)]
    }
}
```

## Error handling

```swift
func loadUser(id: Int) async -> String {
    switch await GetUserRequest(userId: id).request() {
    case .success(let user):
        return user.name
    case .error(.api(let statusCode, _)) where statusCode == 404:
        return "Not found"
    case .error(.noConnection):
        return "You are offline"
    case .error(.timeout):
        return "Timed out"
    case .error(.authNeeded), .error(.authProviderNeeded):
        return "Please log in"
    case .error(.codable(let model, let error)):
        return "Cannot decode \(model): \(error)"
    case .error(let error):
        return error.localizedDescription
    }
}
```

## SwiftUI

The SwiftUI snippets in these examples assume `import SwiftUI`.

```swift
@MainActor
final class UserViewModel: ObservableObject {
    @Published var user: User?
    @Published var errorMessage: String?

    func load(id: Int) async {
        // request() runs on Harbor's actor; results come back here on the main actor.
        switch await GetUserRequest(userId: id).request() {
        case .success(let user):
            self.user = user
        case .error(let error):
            errorMessage = error.localizedDescription
        }
    }
}

struct UserView: View {
    @StateObject private var model = UserViewModel()

    var body: some View {
        Text(model.user?.name ?? model.errorMessage ?? "Loading…")
            .task { await model.load(id: 1) }
    }
}
```

## Headers

```swift
struct LocalizedUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/me"
    let locale: String

    // Computed: may depend on stored properties
    var headerParameters: [String: String]? {
        ["Accept-Language": locale, "X-Request-ID": UUID().uuidString]
    }
}

func configureHeaders() async {
    // Sent with every request; request headers override them; the auth header is applied last
    await Harbor.setDefaultHeaderParameters(["X-Client-Version": "4.0.0", "Accept": "application/json"])
}
```

## Global configuration

```swift
func configure() async {
    await Harbor.setDefaultTimeoutInterval(30)               // per-request idle timeout (default 15 s)
    await Harbor.setDefaultResourceTimeoutInterval(300)      // whole-transfer limit of Harbor-built sessions (default: system, 7 days)
    await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneHour)))
    await Harbor.setLoggingEnabled(true)                    // default: on in DEBUG, off in release
    await Harbor.setHTTPShouldHandleCookies(true)            // default: false

    let delegate = await Harbor.makeURLSessionDelegate()   // keeps pinning / mTLS / redirect policy
    await Harbor.setCustomURLSession(URLSession(configuration: .default, delegate: delegate, delegateQueue: nil))
}
```

## Debug logging for one request

```swift
struct DebugUserRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/me"
    let debugType: HDebugRequestType = .requestAndResponse   // also the default
}
```

The output includes a redacted cURL command, headers, body, status and duration.

## Grouping requests

```swift
enum UsersAPI {
    static let baseURL = "https://api.example.com/v1"

    struct List: HGetRequestProtocol {
        typealias Model = [User]
        let url = "\(UsersAPI.baseURL)/users"
    }

    struct Detail: HGetRequestProtocol {
        typealias Model = User
        let url = "\(UsersAPI.baseURL)/users/{id}"
        let pathParameters: [String: String]?

        init(id: Int) {
            pathParameters = ["id": String(id)]
        }
    }
}

func listUsers() async {
    _ = await UsersAPI.List().request()
    _ = await UsersAPI.Detail(id: 1).request()
}
```

## Retry

```swift
struct ResilientUserRequest: HGetRequestProtocol {
    typealias Model = User
    let url = "https://api.example.com/me"
    // Up to 3 retries on 408/425/429/500/502/503/504 or transient network errors, with backoff + jitter
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3)
}

struct ResilientCreateRequest: HPostRequestProtocol {
    let url = "https://api.example.com/orders"
    var bodyParameters: [String: Any]? { ["sku": "A1"] }
    // POST is only retried after a 5xx/timeout when the endpoint is idempotent (e.g. uses an idempotency key)
    let headerParameters: [String: String]? = ["Idempotency-Key": UUID().uuidString]
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, retryNonIdempotentRequests: true)
}
```

## Related files

- `../protocols.md`: full protocol reference.
- `advanced.md`: streaming, multipart, auth, pagination, cancellation.
- `jrpc.md`: JSON-RPC.
