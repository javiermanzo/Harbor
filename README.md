
<p align="center" width="100%">
    <img width="40%" src="https://raw.githubusercontent.com/javiermanzo/Harbor/main/Resources/Harbor.png"> 
</p>

![Release](https://img.shields.io/github/v/release/javiermanzo/Harbor?style=flat-square)
![CI](https://img.shields.io/github/actions/workflow/status/javiermanzo/Harbor/unit-tests.yml?style=flat-square)
[![Swift](https://img.shields.io/badge/Swift-5.9_6.0-orange?style=flat-square)](https://img.shields.io/badge/Swift-5.9_5.10_6.0-Orange?style=flat-square)
[![Platforms](https://img.shields.io/badge/Platforms-macOS_iOS-yellowgreen?style=flat-square)](https://img.shields.io/badge/Platforms-macOS_iOS_tvOS_watchOS_vision_OS_Linux_Windows_Android-Green?style=flat-square) 
[![Swift Package Manager](https://img.shields.io/badge/Swift_Package_Manager-compatible-orange?style=flat-square)](https://swiftpackageindex.com/javiermanzo/Harbor)


Harbor is a library for making API requests in Swift in a simple way using async/await.

## Table of Contents
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)

  - [Swift Package Manager](#swift-package-manager)
- [Usage](#usage)
  - [Configuration](#configuration)
    - [Default Headers](#default-headers)
    - [Auth Provider](#auth-provider)
    - [Custom URLSession](#custom-urlsession)
    - [Timeout Configuration](#timeout-configuration)
    - [mTLS Support](#mtls-support)
    - [SSL Pinning](#ssl-pinning)
    - [Retry Configuration](#retry-configuration)
  - [Request Protocols](#request-protocols)
    - [HGetRequestProtocol](#hgetrequestprotocol)
    - [HPostRequestProtocol](#hpostrequestprotocol)
    - [HPatchRequestProtocol](#hpatchrequestprotocol)
    - [HPutRequestProtocol](#hputrequestprotocol)
    - [HDeleteRequestProtocol](#hdeleterequestprotocol)
    - [HRequestWithResultProtocol](#hrequestwithresultprotocol)
  - [Request Calling](#request-calling)
  - [Response](#response)
    - [HResponse](#hresponse)
    - [HResponseWithResult](#hresponsewithresult)
  - [Cancel Request](#cancel-request)
  - [Caching](#caching)
    - [Cache Configuration](#cache-configuration)
      - [Global Default Cache](#global-default-cache)
      - [Per-Request Cache](#per-request-cache)
      - [Available Expiration Times](#available-expiration-times)
      - [Max Object Size](#max-object-size)
    - [HCache Performance](#hcache-performance)
    - [Cache Usage](#cache-usage)
      - [Get Cached Data](#get-cached-data)
      - [Clear Specific Cache](#clear-specific-cache)
      - [Clear All Cache](#clear-all-cache)
  - [Streaming Requests](#streaming-requests)
    - [AsyncThrowingStream Support](#asyncthrowingstream-support)
    - [Data Sources](#data-sources)
    - [Stream Usage Examples](#stream-usage-examples)
  - [Debug](#debug)
    - [Sensitive Data in Logs](#sensitive-data-in-logs)
  - [JSON RPC](#json-rpc)
    - [Installation](#installation-1)
    - [Configuration](#configuration-1)
      - [Set URL](#set-url)
      - [Set JSON RPC Version](#set-json-rpc-version)
    - [Request Protocol](#request-protocol)
      - [HJRPCRequestProtocol](#hjrpcrequestprotocol)
    - [Calling a Request](#calling-a-request)
    - [Notifications](#notifications)
    - [Batch Requests](#batch-requests)
    - [Response](#response-1)
- [Mocks](#mocks)
  - [HMock](#hmock)
  - [Register a Mock](#register-a-mock)
  - [Registering a Success Mock](#registering-a-success-mock)
  - [Registering an Error Mock](#registering-an-error-mock)
  - [Using Mocks Only in Debug Mode](#using-mocks-only-in-debug-mode)
  - [Removing a Specific Mock](#removing-a-specific-mock)
  - [Removing All Mocks](#removing-all-mocks)
  - [Complete Example](#complete-example)
- [AI Assistant Skill](#ai-assistant-skill)
- [Contributing](#contributing)
- [Author](#author)
- [License](#license)

## Features

- [x] Rest Requests
- [x] JSON RPC Requests
- [x] Auth provider handler
- [x] Multipart Post Requests
- [x] Retry Requests
- [x] Cancel Request
- [x] Debug Requests
- [x] cURL Command Output
- [x] Default Headers
- [x] Custom URLSession
- [x] mTLS Certificate
- [x] SSL Pinning
- [x] Complete Caching System
- [x] AsyncThrowingStream Support
- [x] Swift 6 Compatible
- [x] Mock Requests

## Requirements

- Swift 5.9+
- iOS 15.0+

## Installation
You can add Harbor to your project using [Swift Package Manager](https://swift.org/package-manager/).

### Swift Package Manager
Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/javiermanzo/Harbor.git")
]
```

Then add the products you need to your target:

```swift
.target(
    dependencies: [
        .product(name: "Harbor", package: "Harbor"),
        .product(name: "HarborJRPC", package: "Harbor") // Only if you need JSON-RPC support
    ]
)
```

## Usage

### Configuration
This provides a centralized way to manage common configuration.

#### Default Headers
You can include default headers in every request.

To configure the default headers:

```swift
await Harbor.setDefaultHeaderParameters([
    "MY_CUSTOM_HEADER": "VALUE"
])
```

#### Auth Provider
You can implement the `HAuthProviderProtocol` if you need to handle authentication. Use the `setAuthProvider` method of the `Harbor` class to set the authentication provider.

You need to create a class that implements `HAuthProviderProtocol`:

```swift
class MyAuthProvider: HAuthProviderProtocol {
    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        // Return a HAuthorizationHeader instance, or nil when no credentials are
        // available (the request is then sent without an authorization header)
    }
    
    func authFailed() async {
        // This method is called when the request receives a 401 status code
    }
}
```

After that, set your Auth provider:

```swift
await Harbor.setAuthProvider(MyAuthProvider())
```

If the request class has the `needsAuth` property set to `true`, Harbor will call the `getAuthorizationHeader` method of the authentication provider to get the `HAuthorizationHeader` instance to set it in the header before executing the request.

#### Custom URLSession
Harbor allows you to set a custom `URLSession` for your requests, providing flexibility for advanced configurations such as custom caching, timeout settings, or additional protocols.

To set a custom `URLSession`, use the `setCustomURLSession` method:

```swift
let customSession = URLSession(configuration: .default)
await Harbor.setCustomURLSession(customSession)
```

#### Timeout Configuration
Harbor allows you to configure the timeout interval for requests. By default, the timeout is 15 seconds.

To set a global default timeout:

```swift
// Set default timeout to 30 seconds
await Harbor.setDefaultTimeoutInterval(30)
```

You can also override the timeout for individual requests:

```swift
struct MyRequest: HGetRequestProtocol {
    let url = "https://api.example.com/data"
    var timeoutInterval: TimeInterval? = 10  // Override global timeout
}
```

#### mTLS Support
Harbor supports mutual TLS (mTLS) for enhanced security in API requests. This feature allows clients to present certificates to the server, ensuring both the client and server authenticate each other.

To set up mTLS, use the `setMTLS` method. The P12 password is supplied through a provider closure, so it is requested once when the identity is extracted instead of being retained:

```swift
let mTLS = HMTLS(p12FileUrl: yourP12FileUrl) { "yourPassword" }
try await Harbor.setMTLS(mTLS)
```

#### SSL Pinning
Harbor supports SSL Pinning to enhance the security of your API requests. SSL Pinning ensures that the client checks the server's certificate against a known pinned public key, adding an additional layer of security.

Pins use the standard format `base64(SHA256(SPKI))` — the SHA-256 of the certificate's SubjectPublicKeyInfo, base64 encoded (supported key types: RSA 2048/4096, EC P-256/P-384).

To generate a pin from a certificate you can use `Harbor.computePin(for:)`:

```swift
if let pin = await Harbor.computePin(for: certificate) {
    await Harbor.setSSLPinningKeys([pin])
}
```

Or with OpenSSL:

```bash
openssl s_client -connect api.example.com:443 -servername api.example.com < /dev/null 2>/dev/null | \
  openssl x509 -pubkey -noout | \
  openssl pkey -pubin -outform der | \
  openssl dgst -sha256 -binary | \
  openssl base64
```

To configure SSL Pinning, use the `setSSLPinningKeys` method. You can provide multiple keys to support key rotation. Malformed pins log a warning and are ignored during validation:

```swift
let sslPinningKeys = [
    "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=", // current certificate
    "GNKGcGj1ue3yRYvqr9t/lz2nkzMU5VZK3QBILcvPJ8U="  // backup / next rotation
]
await Harbor.setSSLPinningKeys(sslPinningKeys)
```

Pins can also be scoped to specific hosts; unconfigured hosts get the default URLSession handling:

```swift
await Harbor.setSSLPinningKeys(sslPinningKeys, forHosts: ["api.example.com"])
```

#### Retry Configuration
Harbor supports automatic retry for failed requests. You can configure the number of retry attempts per request:

```swift
struct MyRequest: HGetRequestProtocol {
    let url = "https://api.example.com/data"
    var retries: Int? = 3  // Will retry up to 3 times on failure
}
```

The default value is `nil` (no retries). When set, Harbor will automatically retry the request on transient failures like network timeouts or server errors.

### Request Protocols
To make a request using Harbor, you need to create a class that implements one of the following protocols.

#### HGetRequestProtocol
Use the `HGetRequestProtocol` protocol if you want to send a GET request.

##### Properties:
- `queryParameters`: A dictionary of query parameters that will be added to the URL.
- `cacheType`: Optional cache configuration for this specific request.

##### Associated Type:
- `Model`: The type that the response will be decoded into.

#### HPostRequestProtocol
Use the `HPostRequestProtocol` protocol if you want to send a POST request.

##### Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either json or multipart.

#### HPatchRequestProtocol
Use the `HPatchRequestProtocol` protocol if you want to send a PATCH request.

##### Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either json or multipart.

#### HPutRequestProtocol
Use the `HPutRequestProtocol` protocol if you want to send a PUT request.

##### Properties:
- `bodyParameters`: A dictionary of parameters that will be included in the body of the request.
- `bodyType`: Specifies the type of data being sent in the body of the request. It can be either json or multipart.

#### HDeleteRequestProtocol
Use the `HDeleteRequestProtocol` protocol if you want to send a DELETE request.

#### HRequestWithResultProtocol
Use the `HRequestWithResultProtocol` protocol if you want to parse the response into a specific model. This protocol requires you to define the type of model you expect in the response.

##### Associated Type:
- `Model`: The type that the response will be decoded into.

### Request Calling
Once the request class is created, you can execute the request using the `request` method.

```swift
Task {
    let response = await MyRequestWithResult().request()
}
```

### Response

#### HResponse
If you use a protocol different from `HGetRequestProtocol` or `HRequestWithResultProtocol`, the result of calling `request()` will be an `HResponse` enum.

```swift
switch response {
case .success:
    break
case .error(let error):
    break
}
```

#### HResponseWithResult
If you use `HGetRequestProtocol` or `HRequestWithResultProtocol`, the result of calling `request()` will be an `HResponseWithResult` enum.

```swift
switch response {
case .success(let result):
    break
case .error(let error):
    break
}
```

### Cancel Request
You can cancel the task of the request if it is running. `request()` will return `cancelled` as an error case.

```swift
let task = Task {
    let response = await MyRequestWithResult().request()
}
task.cancel()
```

### Caching

Harbor includes a complete caching system to optimize the performance of your GET requests (`HGetRequestProtocol`).

#### Cache Configuration

##### Global Default Cache
You can set a global default cache configuration for all requests:

```swift
// Use URLCache-backed automatic HTTP caching (this is the default)
await Harbor.setDefaultCacheType(.urlCache())

// Enable cache globally with custom cache (1 week expiration)
await Harbor.setDefaultCacheType(.custom(HCache.Configuration(expirationTime: .oneWeek)))

// Disable cache globally
await Harbor.setDefaultCacheType(.disabled)
```

##### Per-Request Cache
You can override the default cache type for specific GET requests by implementing `HGetRequestProtocol`:

```swift
class MyGetRequest: HGetRequestProtocol {
    // ... other properties
    
    var cacheType: HCache.CacheType? = .custom(HCache.Configuration(expirationTime: .oneDay, maxObjectSizeInMBs: 20))
}
```

##### Available Expiration Times
Harbor provides convenient time intervals:

```swift
HCache.Configuration(expirationTime: .fiveMinutes)  // 5 minutes
HCache.Configuration(expirationTime: .fifteenMinutes) // 15 minutes
HCache.Configuration(expirationTime: .thirtyMinutes) // 30 minutes
HCache.Configuration(expirationTime: .oneHour)      // 1 hour
HCache.Configuration(expirationTime: .oneDay)       // 1 day
HCache.Configuration(expirationTime: .threeDays)    // 3 days
HCache.Configuration(expirationTime: .oneWeek)      // 1 week (default)
HCache.Configuration(expirationTime: .noExpiration) // No expiration
```

##### Max Object Size
You can also configure the maximum size for cached objects (in MB). The default is 10MB.

```swift
HCache.Configuration(expirationTime: .oneDay, maxObjectSizeInMBs: 50) // Allow up to 50MB
```

The custom cache also lets you limit its total memory and disk capacity (100MB each by default). When the disk capacity is exceeded, the oldest entries are evicted first:

```swift
HCache.Configuration(
    expirationTime: .oneDay,
    memoryCacheCapacityInMBs: 50,
    diskCacheCapacityInMBs: 200
)
```

#### HCache Performance

Harbor offers two cache strategies for GET requests:

- **`.urlCache`** (default): backed by `URLCache`, it provides automatic HTTP caching with ETag/304 revalidation and zero configuration.
- **`.custom(HCache.Configuration)`**: Harbor's own two-level cache — an `NSCache` in-memory layer in front of a single-file-per-key disk store — with explicit expiration and size control, plus conditional revalidation via `ETag`/`Last-Modified` headers.

#### Cache Usage

##### Get Cached Data
Retrieve cached data for a specific GET request:

```swift
let cachedData = await MyGetRequest().cache()
```

##### Clear Specific Cache
Clear cache for a specific GET request:

```swift
await MyGetRequest().clearCache()
```

##### Clear All Cache
Clear all cached data, including the custom cache (memory and disk) and `URLCache.shared`:

```swift
await Harbor.clearAllCache()
```

### Streaming Requests

Harbor supports reactive data streaming with `AsyncThrowingStream` for GET requests (`HGetRequestProtocol`) with both cache and remote data.

#### AsyncThrowingStream Support

The `requestStream()` method allows you to receive data from cache and/or remote sources reactively for GET requests:

```swift
for try await (response, origin) in MyGetRequest().requestStream() {
    switch origin {
    case .cache:
        print("Data from cache: \(response)")
        // Update UI immediately with cached data
    case .remote:
        print("Data from remote: \(response)")
        // Update UI with fresh data from server
    }
}
```

#### Data Sources

You can specify different data source strategies:

##### Cache and Remote (Default)
Get cached data first (if available), then fresh data from remote:

```swift
for try await (response, origin) in request.requestStream(source: .cacheAndRemote) {
    // First emission: cached data (if available)
    // Second emission: fresh remote data
}
```

##### Cache Only
Only retrieve data from cache:

```swift
for try await (response, origin) in request.requestStream(source: .cacheOnly) {
    // Only cached data, throws error if no cache exists
}
```

##### Remote Only
Only retrieve data from remote server:

```swift
for try await (response, origin) in request.requestStream(source: .remoteOnly) {
    // Only fresh data from server
}
```

#### Stream Usage Examples

```swift
private func loadUsers() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // GetUsersRequest must implement HGetRequestProtocol
            for try await (users, origin) in GetUsersRequest().requestStream() {
                await MainActor.run {
                    self.users = users.users
                    if origin == .cache {
                        print("Showing cached data...")
                    } else {
                        print("Updated with fresh data!")
                    }
                }
            }
        } catch {
            print("Error loading users: \(error)")
        }
    }
```

### Debug
You can print debug information about your request using the `HDebugRequestProtocol` protocol. Implement the protocol in the request class.

Debug logging is enabled by default in `#if DEBUG` builds and disabled in release builds. You can configure it programmatically:

```swift
await Harbor.setLoggingEnabled(true) // or false to turn off debug logging
```

```swift
class MyRequest: HRequestWithResultProtocol, HDebugRequestProtocol {
    var debugType: HDebugRequestType = .requestAndResponse
    
    // ...
}
```

`debugType` defines what you want to print in the console. The options are `none`, `request`, `response`, or `requestAndResponse`.

When your request is called, you will see in the Xcode console the information about your request.

### Sensitive Data in Logs
Harbor redacts sensitive data from debug logs and generated cURL commands through two complementary mechanisms:

**Header values** (`Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `Proxy-Authorization`) and cookies are printed as `<redacted>` in cURL output and the structured `headerParameters` log. Matching is case-insensitive.

```swift
// Print real header values (only for advanced debugging, never in production)
await Harbor.setLogSensitiveHeaders(true)
```

**Metadata keys** (in `additionalInfo`, `extraMessages` and error `userInfo`) are redacted automatically via [LogBird](https://github.com/javiermanzo/LogBird). Harbor inherits LogBird's global default keys (`password`, `token`, `authorization`, `auth`, `secret`, `apikey`, `cookie`, `bearer`, `credentials`, `privatekey`), whose separator-insensitive matching already covers HTTP auth fields like `set-cookie`, `x-api-key`, `access_token`, `refresh_token` and `private_key`. Matching is case-insensitive and ignores separators, so `accessToken`, `access-token` and `ACCESS_TOKEN` all match `token`.

Actions are configured via `HLoggingSensitiveKeyAction`:

```swift
// Replace the full set (LogBird's defaults are NOT merged back in)
await Harbor.loggingSensitiveKeys(.set(["signature", "otp"]))

// Extend the current set, keeping the defaults
await Harbor.loggingSensitiveKeys(.add(["signature", "otp"]))

// Restore LogBird's defaults
await Harbor.loggingSensitiveKeys(.reset)

// Remove all keys, disabling redaction entirely (debug only)
await Harbor.loggingSensitiveKeys(.clear)
```

**JSON response bodies** are also redacted in debug logs: when the response `Content-Type` is JSON (or the body looks like JSON), any key containing a sensitive key is printed as `<redacted>`, so login responses like `{"access_token": "...", "refresh_token": "..."}` don't leak tokens. Set `Harbor.setLogSensitiveHeaders(true)` to see the raw body.

Note that matching is **substring-based**: a key is redacted when it contains any sensitive key. This means the `auth` default also matches keys like `author` or `oauth` in response bodies, which will show as `<redacted>` in debug logs even though they are not credentials.

## JSON RPC
Harbor also supports JSON RPC via the `HarborJRPC` package.

### Installation
To use HarborJRPC, add the following import to your file:

```swift
import HarborJRPC
```

With Swift Package Manager, add `.product(name: "HarborJRPC", package: "Harbor")` to your target dependencies.

### Configuration
HarborJRPC only manages the JSON-RPC endpoint URL and protocol version. Network-level settings (timeout, auth provider, mTLS, mocks, logging) are configured through `Harbor`'s API, the same way as for REST requests.

#### Set URL
Use this method to set the URL for the JSON RPC requests:

```swift
await HarborJRPC.setURL(URL(string: "https://api.example.com/rpc")!)
```

You can also set the URL from a string, which throws `HJRPCConfigurationError.invalidURL` if the string is not a valid URL:

```swift
try await HarborJRPC.setURL("https://api.example.com/rpc")
```

#### Set JSON RPC Version
Use this method to set the JSON RPC version:

```swift
// It uses 2.0 as default 
await HarborJRPC.setJRPCVersion("2.0")
```

You can also configure both the URL and the version in a single call:

```swift
await HarborJRPC.configure(url: URL(string: "https://api.example.com/rpc")!, jrpcVersion: "2.0")
```

### Request Protocol

#### HJRPCRequestProtocol
Use the `HJRPCRequestProtocol` protocol if you want to send a JRPC request.

##### Associated Type:
- `Model`: The model that conforms to the `Codable` protocol, representing the expected response structure.

##### Properties:
- `method`: A string that represents the JRPC method to be called.
- `needsAuth`: A boolean indicating whether the request requires authentication. Default is `false`.
- `retries`: The number of retries in case the request fails. Default is `nil`.
- `headers`: An optional dictionary containing any additional headers to be included in the request. Default is `nil`.
- `parameters`: Optional `HJRPCParams` to be included in the request, either `.named([String: Encodable & Sendable])` (encoded as a JSON object) or `.positioned([Encodable & Sendable])` (encoded as a JSON array). Default is `nil`.
- `isNotification`: A boolean indicating whether the request is a JSON-RPC notification. Notifications do not carry an `id` and the server does not respond to them. Default is `false`.
- `requestID`: An optional `HJRPCId` (`.string`, `.number` or `.null`) to send as the request identifier. Default is `nil`, which generates a UUID-based identifier.

```swift
struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_getBalance"

    let address: String
    let block: String

    var parameters: HJRPCParams? {
        .positioned([address, block])
    }
}
```

### Calling a Request
Once the request is created, you can execute it using `requestResult()`, which returns an `HJRPCResponse`:

```swift
let response = await GetBalanceRequest(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", block: "latest").requestResult()

switch response {
case .success(let balance):
    break
case .error(let error):
    break
}
```

If you prefer throwing code, use `request()`, which returns the decoded model or throws an `HJRPCRequestError`:

```swift
do {
    let balance = try await GetBalanceRequest(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", block: "latest").request()
} catch {
    // Handle HJRPCRequestError
}
```

Server errors are delivered as `HJRPCRequestError.jrpcError`, wrapping an `HJRPCError` with the `code`, `message` and optional `data` returned by the server.

### Notifications
Set `isNotification` to `true` and call `notify()` to send a JSON-RPC notification. Notifications do not include an `id` and the server does not respond to them. Calling `notify()` on a request that is not a notification throws `HJRPCRequestError.invalidRequest`.

```swift
struct UnsubscribeRequest: HJRPCRequestProtocol {
    typealias Model = Bool
    let method: String = "eth_unsubscribe"
    let isNotification: Bool = true

    var parameters: HJRPCParams? {
        .positioned(["0x123"])
    }
}

try await UnsubscribeRequest().notify()
```

### Batch Requests
Use `HarborJRPC.batch(_:)` to send several JSON-RPC requests as a single batch call:

```swift
let responses = await HarborJRPC.batch([
    GetBlockNumberRequest(),
    GetBalanceRequest(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb", block: "latest")
])

for response in responses {
    switch response {
    case .success(let id, let result):
        break // result is the raw HJSONValue returned for the request with the given id
    case .error(let id, let error):
        break
    }
}
```

Notifications included in a batch do not produce a response element. Servers may reorder responses, so each `HJRPCBatchResponse` is paired with the identifier echoed by the server.

### Response
The result of calling `requestResult()` is an `HJRPCResponse`:

```swift
switch response {
case .success(let result):
    break
case .error(let error):
    break
}
```

## Mocks
Harbor allows you to register and manage mocks to facilitate testing your API requests.

### HMock
Use `HMock` to declare mock responses for your requests.

#### Properties:
- `request`: The request type that conforms to `HRequestBaseRequestProtocol` for which the mock is being set.
- `statusCode`: The HTTP status code to return.
- `jsonResponse`: A `String` representing the JSON response. This will be decoded as the expected model for your request.
- `error`: An optional `HRequestError` if you want to simulate an error response.
- `delay`: An optional delay (in seconds) before returning the mock response, to simulate network latency.
- `headers`: An optional dictionary of HTTP response headers (e.g. `Cache-Control`, `ETag`) to simulate server caching behavior.

### Register a Mock
To register a mock, use the `register(mock:)` method. This will allow you to simulate responses instead of making actual API calls.

```swift
let mock = HMock(
    ///
)
await Harbor.register(mock: mock)
```

### Registering a Success Mock

```swift
let jsonResponse = """
    { "name": "John Doe" }
"""
let mock = HMock(
    request: MyGetUsersRequest.self,
    statusCode: 200,
    jsonResponse: jsonResponse
)
await Harbor.register(mock: mock)
```

### Registering an Error Mock

```swift
let mock = HMock(
    request: MyGetUsersRequest.self,
    statusCode: 401,
    error: .authNeeded
)
await Harbor.register(mock: mock)
```

### Using Mocks Only in Debug Mode
You can configure mocks to only be used in #DEBUG, preventing them from affecting production environments. The default value is *true*.

```swift
await Harbor.setMocksOnlyInDebug(false)
```

### Removing a Specific Mock
If you need to remove a specific mock, use the `remove(mock:)` method.

```swift
await Harbor.remove(mock: mock)
```

### Removing All Mocks
To clear all registered mocks, use the `removeAllMocks()` method.

```swift
await Harbor.removeAllMocks()
```

### Complete Example
Below is a complete example demonstrating how to set up and use mocks with Harbor:

```swift

Task {
    let jsonResponse = """
        { "users": [{ "id": 1, "name": "Alice" }] }
    """
    let userMock = HMock(
        request: MyGetUsersRequest.self,
        statusCode: 200,
        jsonResponse: jsonResponse
    )

    // Register the mock
    await Harbor.register(mock: userMock)

    // Perform a request that will use the registered mock
    let response = await MyGetUsersRequest().request()
    switch response {
    case .success(let users):
        // You will receive the mocked response here
        print("Users:", users)
    case .error(let error):
        break
    }
}
```

## AI Assistant Skill

Harbor comes with a built-in skill for Claude and other AI coding assistants. If you are using an AI assistant (like Claude Code, Cursor, GitHub Copilot, or similar), it can automatically understand Harbor's architecture, protocols, and best practices by checking the `skill` directory. 

To use it, just ask your AI assistant to "use the harbor skill" or simply mention that you are using the Harbor networking framework. The AI will read the documentation in `skill` and adhere to Harbor's conventions for creating requests, caching, authentication, and writing tests.

## Contributing
If you run into any problems, please submit an [issue](https://github.com/javiermanzo/Harbor/issues). [Pull requests](https://github.com/javiermanzo/Harbor/pulls) are also welcome!

## Author
Harbor was created by [Javier Manzo](https://www.linkedin.com/in/javiermanzo/).

## License
Harbor is available under the MIT license. See the [LICENSE](https://github.com/javiermanzo/Harbor/blob/main/LICENSE.md) file for more info.

