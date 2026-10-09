# Harbor Advanced Examples

Shared models:

```swift
struct Photo: Codable, Sendable {
    let id: Int
    let url: String
}

struct Post: Codable, Sendable {
    let id: Int
    let title: String
}

struct Page<Item: Codable & Sendable>: Codable, Sendable {
    let items: [Item]
    let nextCursor: String?
}
```

## Multipart uploads

Use `multipartBody` with `HFormValue`. When the body contains files, Harbor writes it to a temporary file in 64 KB chunks and uploads from disk, so large files are never loaded into memory. The temporary file is deleted after each attempt.

```swift
struct UploadPhotoRequest: HPostRequestProtocol {
    let url = "https://api.example.com/photos"
    let needsAuth = true
    let fileURL: URL
    let caption: String

    var bodyParameters: [String: Any]? { nil }

    var multipartBody: [String: HFormValue]? {
        [
            "caption": .text(caption),
            "photo": .file(url: fileURL, mimeType: "image/jpeg", fileName: nil)   // filename = fileURL.lastPathComponent
        ]
    }
}

struct UploadAlbumRequest: HPostRequestProtocol {
    let url = "https://api.example.com/albums"
    let files: [URL]

    var bodyParameters: [String: Any]? { nil }

    var multipartBody: [String: HFormValue]? {
        var fields: [String: HFormValue] = ["title": .text("Holidays")]
        for (index, file) in files.enumerated() {
            fields["photo\(index)"] = .file(url: file, mimeType: "image/png", fileName: "photo\(index).png")
        }
        return fields
    }
}

func upload(fileURL: URL) async {
    switch await UploadPhotoRequest(fileURL: fileURL, caption: "Sunset").request() {
    case .success:
        print("Uploaded")
    case .error(.malformedRequest(let reason)):
        print("Cannot build the body: \(reason ?? "")")   // e.g. unreadable file
    case .error(let error):
        print(error)
    }
}
```

## Streaming (cache + remote)

`requestStream(source:)` yields at most two elements: the cached value (`.cache`, when `cache()` has one) and then the remote value (`.remote`). Cancelling the consuming task cancels the underlying request.

```swift
struct TimelineRequest: HGetRequestProtocol {
    typealias Model = [Post]
    let url = "https://api.example.com/timeline"
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .fifteenMinutes))
}

@MainActor
final class TimelineViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isStale = false
    @Published var error: Error?

    func load() async {
        do {
            for try await (posts, origin) in TimelineRequest().requestStream(source: .cacheAndRemote) {
                self.posts = posts
                isStale = origin == .cache
            }
        } catch {
            // Remote failure (cached posts, if any, stay on screen)
            self.error = error
        }
    }
}

struct TimelineView: View {
    @StateObject private var model = TimelineViewModel()

    var body: some View {
        List(model.posts, id: \.id) { post in
            Text(post.title)
        }
        .task { await model.load() }
    }
}

func cacheOnlyAndRemoteOnly() async {
    // .cacheOnly: one element or HRequestError.noCachedDataFound
    if let cached = try? await TimelineRequest().requestStream(source: .cacheOnly).first(where: { _ in true }) {
        print("cached", cached.response.count)
    }
    // .remoteOnly: one element or the request error
    do {
        for try await element in TimelineRequest().requestStream(source: .remoteOnly) {
            print("remote", element.response.count)
        }
    } catch {
        print(error)
    }
}
```

## OAuth2 with refresh

```swift
actor OAuthTokenStore {
    private var accessToken: String?
    private var refreshToken: String?

    func current() -> String? { accessToken }

    func save(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }

    func currentRefreshToken() -> String? { refreshToken }
}

struct TokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
}

struct RefreshTokenRequest: HPostRequestProtocol, HRequestWithResultProtocol {
    typealias Model = TokenResponse
    let url = "https://auth.example.com/oauth/token"
    let refreshToken: String

    var bodyParameters: [String: Any]? {
        ["grant_type": "refresh_token", "refresh_token": refreshToken]
    }
}

final class OAuth2Provider: HAuthProviderProtocol {
    let store: OAuthTokenStore

    init(store: OAuthTokenStore) {
        self.store = store
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        guard let token = await store.current() else { return nil }
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        // Harbor calls this at most once per request and coalesces concurrent 401s that used
        // the same header, so a burst of failures triggers a single refresh. It is skipped when
        // getAuthorizationHeader() already returns a header different from the rejected one.
        guard let refresh = await store.currentRefreshToken() else { return }
        let response: HResponseWithResult<TokenResponse> = await RefreshTokenRequest(refreshToken: refresh).request()
        switch response {
        case .success(let tokens):
            await store.save(access: tokens.accessToken, refresh: tokens.refreshToken)
        case .error:
            await store.save(access: nil, refresh: nil)   // header becomes nil → request fails with .authNeeded
        }
    }
}

func logout(store: OAuthTokenStore) async {
    await store.save(access: nil, refresh: nil)
    await Harbor.clearAllCache()   // per-credential cache entries are not removed automatically
}
```

`RefreshTokenRequest` has `needsAuth == false`, so it never re-enters the provider.

## Custom URLSession

```swift
func configureSession() async {
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    configuration.httpMaximumConnectionsPerHost = 4
    configuration.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)

    // Configure pins / mTLS BEFORE creating the delegate: it snapshots them.
    let delegate = await Harbor.makeURLSessionDelegate()
    await Harbor.setCustomURLSession(URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil))
}
```

A custom session without Harbor's delegate bypasses SSL pinning, mTLS and cross-origin credential stripping, and Harbor logs a warning. To use your own delegate, forward to an `HURLSessionDelegate` (see `../security.md`). Default timeouts still apply per request. `setDefaultResourceTimeoutInterval` doesn't apply to custom sessions.

## Error recovery

```swift
enum LoadState<Value> {
    case loaded(Value)
    case offline
    case needsLogin
    case failed(String)
}

func loadPosts() async -> LoadState<[Post]> {
    switch await TimelineRequest().request() {
    case .success(let posts):
        return .loaded(posts)
    case .error(let error):
        switch error {
        case .noConnection, .cannotFindHost, .cannotConnectToHost, .timeout:
            if let cached = await TimelineRequest().cache() {
                return .loaded(cached)
            }
            return .offline
        case .authNeeded, .authProviderNeeded:
            return .needsLogin
        case .certificate:
            return .failed("Secure connection failed")
        case .api(let status, _) where status >= 500:
            return .failed("Server error \(status)")
        default:
            return .failed(error.localizedDescription)
        }
    }
}
```

Harbor already serves a fresh or `stale-if-error` entry for `.custom`-cached GET requests, and the stored `URLCache` response for `.urlCache` requests, before returning `.noConnection`. For timeouts and unreachable hosts, Harbor only falls back to `stale-if-error` entries. The explicit `cache()` fallback above adds any entry that is not stale.

## Parallel requests

```swift
struct PhotoRequest: HGetRequestProtocol {
    typealias Model = Photo
    let url = "https://api.example.com/photos/{id}"
    let pathParameters: [String: String]?

    init(id: Int) {
        pathParameters = ["id": String(id)]
    }
}

func loadDashboard() async {
    async let timeline = TimelineRequest().request()
    async let photo = PhotoRequest(id: 1).request()
    let (timelineResult, photoResult) = await (timeline, photo)
    print(timelineResult, photoResult)
}

func loadPhotos(ids: [Int]) async -> [Photo] {
    await withTaskGroup(of: Photo?.self) { group in
        for id in ids {
            group.addTask {
                if case .success(let photo) = await PhotoRequest(id: id).request() { return photo }
                return nil
            }
        }
        var photos: [Photo] = []
        for await photo in group {
            if let photo { photos.append(photo) }
        }
        return photos
    }
}
```

## Pagination

```swift
struct PostsPageRequest: HGetRequestProtocol {
    typealias Model = Page<Post>
    let url = "https://api.example.com/posts"
    let queryParameters: [String: String]?

    init(cursor: String?, limit: Int = 50) {
        var query = ["limit": String(limit)]
        if let cursor { query["cursor"] = cursor }
        queryParameters = query
    }
}

func loadAllPosts() async throws -> [Post] {
    var posts: [Post] = []
    var cursor: String?
    repeat {
        switch await PostsPageRequest(cursor: cursor).request() {
        case .success(let page):
            posts += page.items
            cursor = page.nextCursor
        case .error(let error):
            throw error
        }
    } while cursor != nil
    return posts
}
```

## Cancellation

Harbor has no request-ID registry. Cancel the Swift `Task` instead. The request returns `.error(.cancelled)`, including while it waits for a retry backoff or a mock delay.

```swift
@MainActor
final class SearchViewModel: ObservableObject {
    @Published var results: [Post] = []
    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)   // debounce
            guard !Task.isCancelled else { return }
            switch await TimelineRequest().request() {
            case .success(let posts):
                results = posts
            case .error(.cancelled):
                break
            case .error(let error):
                print(error)
            }
        }
    }
}
```

## Debugging

```swift
struct TracedTimelineRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = [Post]
    let url = "https://api.example.com/timeline"
    let debugType: HDebugRequestType = .requestAndResponse
}

func enableLogs() async {
    await Harbor.setLoggingEnabled(true)                 // works in release builds too
    await Harbor.updateLogSensitiveKeys(.add(["otp"]))   // redact extra fields
}
```

Logged values (headers, query, body, cURL, response body, `.api` error previews) are redacted. `Harbor.setLogSensitiveValues(true)` shows them in clear, for local debugging only.

## Related files

- `basic.md`, `jrpc.md`.
- `../cache.md`, `../security.md`, `../testing.md`.
