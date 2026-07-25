# Harbor Advanced Examples

Advanced patterns and techniques for Harbor networking.

## Multipart POST Requests

### Upload Single File

```swift
struct UploadImageRequest: HPostRequestProtocol {
    typealias Model = UploadResponse
    let url: String = "https://api.example.com/images/upload"
    
    let imageData: Data
    let filename: String
    
    var bodyParameters: [String: Any]? {
        [
            "image": imageData,
            "filename": filename
        ]
    }
    var bodyType: HRequestDataType { .multipart }
}

// Usage
guard let image = UIImage(named: "photo"),
      let imageData = image.jpegData(compressionQuality: 0.8) else {
    return
}

let response = await UploadImageRequest(
    imageData: imageData,
    filename: "photo.jpg"
).request()
```

### Upload File with Metadata

```swift
struct UploadDocumentRequest: HPostRequestProtocol {
    typealias Model = DocumentResponse
    let url: String = "https://api.example.com/documents/upload"
    
    let fileData: Data
    let filename: String
    let title: String
    let description: String
    let category: String
    
    var bodyParameters: [String: Any]? {
        [
            "document": fileData,
            "title": title,
            "description": description,
            "category": category
        ]
    }
    var bodyType: HRequestDataType { .multipart }
}
```

### Upload Multiple Files

```swift
struct UploadMultipleImagesRequest: HPostRequestProtocol {
    typealias Model = BatchUploadResponse
    let url: String = "https://api.example.com/images/batch"
    
    let images: [(data: Data, filename: String)]
    
    var bodyParameters: [String: Any]? {
        var params: [String: Any] = [:]
        for (index, image) in images.enumerated() {
            params["images[\(index)]"] = image.data
        }
        return params
    }
    var bodyType: HRequestDataType { .multipart }
}
```

## Streaming Requests

### Cache and Remote Stream

```swift
struct GetUserRequest: HGetRequestProtocol {
    typealias Model = User
    let userId: String
    var url: String { "https://api.example.com/users/\(userId)" }
    let cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneHour))
}

// Stream will emit twice: first from cache (if exists), then from network
for try await (user, origin) in GetUserRequest(userId: "123").requestStream(source: .cacheAndRemote) {
    await MainActor.run {
        // Update UI
        self.user = user
        
        switch origin {
        case .cache:
            // Show as cached data (maybe with refresh indicator)
            self.showRefreshIndicator = true
        case .remote:
            // Fresh data from network
            self.showRefreshIndicator = false
        }
    }
}
```

### SwiftUI Streaming Pattern

```swift
struct UserProfileView: View {
    @State private var user: User?
    @State private var isLoadingFromNetwork = false
    @State private var errorMessage: String?
    
    let userId: String
    
    var body: some View {
        VStack {
            if let user = user {
                ProfileContent(user: user)
                
                if isLoadingFromNetwork {
                    ProgressView("Updating...")
                        .padding()
                }
            } else {
                ProgressView("Loading...")
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
            }
        }
        .task {
            await loadUser()
        }
        .refreshable {
            await refreshUser()
        }
    }
    
    func loadUser() async {
        do {
            for try await (loadedUser, origin) in GetUserRequest(userId: userId).requestStream() {
                await MainActor.run {
                    self.user = loadedUser
                    self.errorMessage = nil
                    
                    if origin == .cache {
                        // Cached data loaded, network request in progress
                        self.isLoadingFromNetwork = true
                    } else {
                        // Fresh data loaded
                        self.isLoadingFromNetwork = false
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoadingFromNetwork = false
            }
        }
    }
    
    func refreshUser() async {
        // Clear cache and force network fetch
        let request = GetUserRequest(userId: userId)
        await request.clearCache()
        await loadUser()
    }
}
```

### Cache-Only Stream

```swift
// Only check cache, no network request
for try await (user, _) in GetUserRequest(userId: "123").requestStream(source: .cacheOnly) {
    print("Found cached user: \(user.name)")
}

// If no cache exists, stream completes without emitting any values
```

### Remote-Only Stream

```swift
// Skip cache, always fetch from network
for try await (user, _) in GetUserRequest(userId: "123").requestStream(source: .remoteOnly) {
    print("Fresh user from network: \(user.name)")
}

// Cache is still updated for future requests
```

## Authentication Patterns

### Complete OAuth2 Flow

```swift
final class OAuth2Manager: HAuthProviderProtocol, @unchecked Sendable {
    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiration: Date?
    
    private let clientId: String
    private let clientSecret: String
    private let tokenEndpoint: String
    
    init(clientId: String, clientSecret: String, tokenEndpoint: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.tokenEndpoint = tokenEndpoint
    }
    
    // MARK: - HAuthProviderProtocol
    
    func getHeaders() async -> [String: String] {
        guard let token = accessToken else {
            return [:]
        }
        return ["Authorization": "Bearer \(token)"]
    }
    
    func isTokenExpired() async -> Bool {
        guard let expiration = tokenExpiration else {
            return true
        }
        // Refresh 60 seconds before expiration
        return Date().addingTimeInterval(60) > expiration
    }
    
    func refreshToken() async throws {
        guard let refreshToken = refreshToken else {
            throw OAuth2Error.noRefreshToken
        }
        
        struct RefreshRequest: HPostRequestProtocol {
            typealias Model = TokenResponse
            let url: String
            var bodyParameters: [String: Any]?
        }
        
        let request = RefreshRequest(
            url: tokenEndpoint,
            bodyParameters: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientId,
                "client_secret": clientSecret
            ]
        )
        
        let response = await request.request()
        switch response {
        case .success(let tokens):
            self.accessToken = tokens.accessToken
            self.refreshToken = tokens.refreshToken
            self.tokenExpiration = Date().addingTimeInterval(tokens.expiresIn)
            
            // Save to secure storage
            try await saveTokens(tokens)
            
        case .error(let error):
            throw error
        }
    }
    
    // MARK: - Public Methods
    
    func login(username: String, password: String) async throws {
        struct LoginRequest: HPostRequestProtocol {
            typealias Model = TokenResponse
            let url: String
            var bodyParameters: [String: Any]?
        }
        
        let request = LoginRequest(
            url: tokenEndpoint,
            bodyParameters: [
                "grant_type": "password",
                "username": username,
                "password": password,
                "client_id": clientId,
                "client_secret": clientSecret
            ]
        )

        let response = await request.request()
        switch response {
        case .success(let tokens):
            self.accessToken = tokens.accessToken
            self.refreshToken = tokens.refreshToken
            self.tokenExpiration = Date().addingTimeInterval(tokens.expiresIn)
            
            // Save to secure storage
            try await saveTokens(tokens)
            
        case .error(let error):
            throw error
        }
    }
    
    func logout() async {
        accessToken = nil
        refreshToken = nil
        tokenExpiration = nil
        
        // Clear secure storage
        await clearTokens()
    }
    
    // MARK: - Storage (implement with Keychain)
    
    private func saveTokens(_ tokens: TokenResponse) async throws {
        // Save to Keychain
    }
    
    private func clearTokens() async {
        // Clear from Keychain
    }
}

struct TokenResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

enum OAuth2Error: Error {
    case noRefreshToken
    case invalidCredentials
}
```

### Using OAuth2 Manager

```swift
// In AppDelegate or app initialization
let oauth2 = OAuth2Manager(
    clientId: "your-client-id",
    clientSecret: "your-client-secret",
    tokenEndpoint: "https://auth.example.com/oauth/token"
)

// Login
try await oauth2.login(username: "user@example.com", password: "password")

// Set as auth provider
await Harbor.setAuthProvider(oauth2)

// Now all authenticated requests work automatically
struct GetPrivateDataRequest: HGetRequestProtocol {
    typealias Model = PrivateData
    let url = "https://api.example.com/private"
    let needsAuth = true
}

let response = await GetPrivateDataRequest().request()
// Auth headers added automatically, token refreshed if needed
```

## Custom URLSession

### URLSession with Custom Configuration

```swift
func configureCustomURLSession() async {
    let configuration = URLSessionConfiguration.default
    
    // Timeouts
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 300
    
    // Connectivity
    configuration.waitsForConnectivity = true
    configuration.allowsCellularAccess = true
    configuration.allowsExpensiveNetworkAccess = true
    configuration.allowsConstrainedNetworkAccess = true
    
    // HTTP settings
    configuration.httpMaximumConnectionsPerHost = 6
    configuration.httpShouldSetCookies = false
    configuration.httpShouldUsePipelining = true
    
    // Cache policy
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil // Disable URLCache, use Harbor's cache
    
    let session = URLSession(configuration: configuration)
    await Harbor.setCustomURLSession(session)
}
```

### URLSession with Custom Delegate

```swift
class CustomURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Custom certificate validation logic
        completionHandler(.performDefaultHandling, nil)
    }
}

let delegate = CustomURLSessionDelegate()
let session = URLSession(
    configuration: .default,
    delegate: delegate,
    delegateQueue: nil
)

await Harbor.setCustomURLSession(session)
```

## Advanced Error Handling

### Comprehensive Error Recovery

```swift
func fetchDataWithErrorRecovery<T: HGetRequestProtocol>(
    request: T,
    maxRetries: Int = 3
) async -> T.Model? where T.Model: Decodable & Sendable {
    
    for attempt in 1...maxRetries {
        let response = await request.request()
        
        switch response {
        case .success(let data):
            return data
            
        case .error(let error):
            switch error {
            case .authNeeded:
                // Try to refresh auth
                if let authProvider = await getAuthProvider() {
                    do {
                        try await authProvider.refreshToken()
                        // Retry with new token
                        continue
                    } catch {
                        return nil
                    }
                }
                return nil
                
            case .noConnection:
                // Wait and retry
                if attempt < maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000) // Exponential backoff
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                return nil
                
            case .api(let statusCode, _):
                if statusCode >= 500 && attempt < maxRetries {
                    // Retry server errors
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                return nil
                
            case .timeout:
                // Retry timeouts
                if attempt < maxRetries {
                    continue
                }
                return nil
                
            default:
                // Don't retry other errors
                return nil
            }
        }
    }
    
    return nil
}

// Usage
if let data = await fetchDataWithErrorRecovery(request: GetDataRequest()) {
    print("Data: \(data)")
} else {
    print("Failed after retries")
}
```

### Error Logging and Monitoring

```swift
struct MonitoredRequest<T: HGetRequestProtocol>: HGetRequestProtocol {
    typealias Model = T.Model
    
    let wrappedRequest: T
    let analyticsService: AnalyticsService
    
    var url: String { wrappedRequest.url }
    var queryParameters: [String: Any]? { wrappedRequest.queryParameters }
    var headerParameters: [String: String]? {
        get { wrappedRequest.headerParameters }
        set { }
    }
    var needsAuth: Bool { wrappedRequest.needsAuth }
    var cacheType: HCache.CacheType? { wrappedRequest.cacheType }
    
    func request() async -> HResponseWithResult<Model> {
        let startTime = Date()
        let response = await wrappedRequest.request()
        let duration = Date().timeIntervalSince(startTime)
        
        // Log metrics
        await analyticsService.logAPICall(
            endpoint: url,
            duration: duration,
            success: response.isSuccess
        )
        
        // Log errors
        if case .error(let error) = response {
            await analyticsService.logError(
                endpoint: url,
                error: error
            )
        }
        
        return response
    }
}
```

## Request Batching

### Parallel Requests

```swift
func loadDashboardData() async -> DashboardData? {
    async let userResponse = GetUserRequest(userId: "123").request()
    async let postsResponse = GetUserPostsRequest(userId: "123").request()
    async let statsResponse = GetUserStatsRequest(userId: "123").request()
    
    let (user, posts, stats) = await (userResponse, postsResponse, statsResponse)
    
    guard case .success(let userData) = user,
          case .success(let postsData) = posts,
          case .success(let statsData) = stats else {
        return nil
    }
    
    return DashboardData(
        user: userData,
        posts: postsData,
        stats: statsData
    )
}
```

### Task Group Pattern

```swift
func loadMultipleUsers(userIds: [String]) async -> [User] {
    await withTaskGroup(of: User?.self) { group in
        for userId in userIds {
            group.addTask {
                let response = await GetUserRequest(userId: userId).request()
                if case .success(let user) = response {
                    return user
                }
                return nil
            }
        }
        
        var users: [User] = []
        for await user in group {
            if let user = user {
                users.append(user)
            }
        }
        return users
    }
}
```

## Pagination

### Offset-Based Pagination

```swift
struct PaginatedListRequest<T: Codable & Sendable>: HGetRequestProtocol {
    typealias Model = PaginatedResponse<T>
    
    let url: String
    let page: Int
    let limit: Int
    
    var queryParameters: [String: Any]? {
        return [
            "page": page,
            "limit": limit
        ]
    }
}

struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let page: Int
    let totalPages: Int
    let totalItems: Int
}

// Usage
func loadAllUsers() async -> [User] {
    var allUsers: [User] = []
    var currentPage = 1
    var hasMore = true
    
    while hasMore {
        let request = PaginatedListRequest<User>(
            url: "https://api.example.com/users",
            page: currentPage,
            limit: 50
        )
        
        let response = await request.request()
        
        switch response {
        case .success(let paginatedData):
            allUsers.append(contentsOf: paginatedData.data)
            hasMore = currentPage < paginatedData.totalPages
            currentPage += 1
        case .error:
            hasMore = false
        }
    }
    
    return allUsers
}
```

### Cursor-Based Pagination

```swift
struct CursorPaginatedRequest<T: Codable & Sendable>: HGetRequestProtocol {
    typealias Model = CursorPaginatedResponse<T>
    
    let url: String
    let cursor: String?
    let limit: Int
    
    var queryParameters: [String: Any]? {
        var params: [String: Any] = ["limit": limit]
        if let cursor = cursor {
            params["cursor"] = cursor
        }
        return params
    }
}

struct CursorPaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    let data: [T]
    let nextCursor: String?
    let hasMore: Bool
}

// Usage
func loadAllPosts() async -> [Post] {
    var allPosts: [Post] = []
    var cursor: String?
    
    repeat {
        let request = CursorPaginatedRequest<Post>(
            url: "https://api.example.com/posts",
            cursor: cursor,
            limit: 50
        )
        
        let response = await request.request()
        
        guard case .success(let paginatedData) = response else {
            break
        }
        
        allPosts.append(contentsOf: paginatedData.data)
        cursor = paginatedData.nextCursor
        
        if !paginatedData.hasMore {
            break
        }
    } while cursor != nil
    
    return allPosts
}
```

## Request Cancellation

### Cancellable Request

```swift
class DataLoader {
    private var currentTask: Task<Void, Never>?
    
    func loadData() {
        // Cancel previous request
        currentTask?.cancel()
        
        currentTask = Task {
            let response = await GetDataRequest().request()
            
            guard !Task.isCancelled else {
                print("Request cancelled")
                return
            }
            
            switch response {
            case .success(let data):
                await updateUI(with: data)
            case .error(let error):
                if case .cancelled = error {
                    print("Request was cancelled")
                } else {
                    await showError(error)
                }
            }
        }
    }
    
    func cancelLoad() {
        currentTask?.cancel()
    }
}
```

## Debug Mode

### Debug Request

```swift
struct DebugGetRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = User
    let url: String = "https://api.example.com/user"
    
    // Debug configuration
    var debugType: HDebugRequestType = .requestAndResponse
}

// Enable logging globally
await Harbor.setLoggingEnabled(true)

// Execute - will print cURL command and response
let response = await DebugGetRequest().request()

// Output:
// curl -X GET "https://api.example.com/user" \
//   -H "Content-Type: application/json" \
//   -H "Accept: application/json"
//
// Response: { "id": 1, "name": "John" }
```

## Related Files

**Advanced Examples:**
- `Example/HarborExample/RequestsView.swift` - Complete implementation
- `Example/HarborExample/Requests/` - Various request types

**More Examples:**
- [basic.md](basic.md) - Basic patterns
- [jrpc.md](jrpc.md) - JSON-RPC examples
