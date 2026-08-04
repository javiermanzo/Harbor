# Harbor Security Guide

Complete guide to Harbor's security features: mTLS, SSL Pinning, and Authentication.

## Overview

Harbor provides three layers of security for network communications:

1. **mTLS (Mutual TLS)**: Client certificate authentication
2. **SSL Pinning**: Certificate validation against known public keys
3. **Authentication Provider**: Custom authentication token management

## mTLS (Mutual TLS)

### What is mTLS?

Mutual TLS extends standard TLS by requiring both the server and client to authenticate with certificates. This provides:

- **Two-way authentication**: Server validates client, client validates server
- **Enhanced security**: Client identity verified via certificate
- **Common use cases**: Banking apps, enterprise APIs, IoT devices

### Configuration

**Location**: `Sources/Harbor/Request/HmTLS.swift`

```swift
struct HmTLS: Sendable {
    let p12FileUrl: URL
    let password: String
}
```

### Setting Up mTLS

#### Step 1: Obtain PKCS12 Certificate

You need a `.p12` file containing:
- Client certificate
- Private key
- (Optional) Certificate chain

**File location options:**
- App bundle: `Bundle.main.url(forResource:withExtension:)`
- Documents directory
- Secure storage (Keychain for sensitive deployments)

#### Step 2: Configure Harbor

```swift
// In AppDelegate or app initialization
Task {
    guard let p12Url = Bundle.main.url(forResource: "client-cert", withExtension: "p12") else {
        print("Certificate not found")
        return
    }
    
    let mtls = HmTLS(p12FileUrl: p12Url, password: "your-certificate-password")
    await Harbor.setMTLS(mtls)
}
```

#### Step 3: Make Requests

Once configured, all requests automatically use the client certificate:

```swift
struct SecureRequest: HGetRequestProtocol {
    typealias Model = SecureData
    let url = "https://secure-api.example.com/data"
}

// Automatically includes client certificate
let response = await SecureRequest().request()
```

### PKCS12 Loading Process

**Location**: `Sources/Harbor/Utils/PKCS12.swift`

Harbor internally handles:
1. Loading PKCS12 data from file
2. Extracting identity (certificate + private key)
3. Extracting certificate chain
4. Creating URLCredential with client identity **and the full certificate chain** (intermediates are sent during the TLS handshake)

**Error Handling:**
```swift
// Harbor logs errors if certificate loading fails
// Check console for messages like:
// "Failed to load PKCS12 file"
// "Failed to import PKCS12 data"
```

### Example: Complete Setup

```swift
import Harbor

@main
struct MyApp: App {
    init() {
        configureMTLS()
    }
    
    func configureMTLS() {
        Task {
            do {
                // Load certificate from bundle
                guard let certUrl = Bundle.main.url(
                    forResource: "client-certificate",
                    withExtension: "p12"
                ) else {
                    throw NSError(domain: "Certificate not found", code: 1)
                }
                
                // Read password from secure storage (example)
                let password = try loadCertificatePassword()
                
                // Configure mTLS
                let mtls = HmTLS(p12FileUrl: certUrl, password: password)
                await Harbor.setMTLS(mtls)
                
                print("mTLS configured successfully")
            } catch {
                print("Failed to configure mTLS: \(error)")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Testing mTLS

**Test Server**: Use https://certauth.cryptomix.com for testing

```swift
struct MTLSTestRequest: HGetRequestProtocol {
    typealias Model = MTLSResponse
    let url = "https://certauth.cryptomix.com/json"
}

struct MTLSResponse: Codable {
    let success: Bool
    let message: String
}

// Execute test
let response = await MTLSTestRequest().request()
switch response {
case .success(let result):
    print("mTLS working: \(result.message)")
case .error(let error):
    print("mTLS failed: \(error)")
}
```

### mTLS Best Practices

1. **Secure Password Storage**
```swift
// Don't hardcode passwords
// ❌ Bad
let mtls = HmTLS(p12FileUrl: url, password: "hardcoded-password")

// ✅ Good - use Keychain
let password = try KeychainManager.getCertificatePassword()
let mtls = HmTLS(p12FileUrl: url, password: password)
```

2. **Certificate Rotation**
```swift
// Support certificate updates
func updateClientCertificate(newCertUrl: URL, password: String) async {
    let mtls = HmTLS(p12FileUrl: newCertUrl, password: password)
    await Harbor.setMTLS(mtls)
}
```

3. **Error Recovery**
```swift
// Handle certificate errors gracefully
let response = await request.request()
switch response {
case .error(.api(let code, _)) where code == 403:
    // Certificate might be expired or invalid
    await promptCertificateRenewal()
default:
    break
}
```

## SSL Pinning

### What is SSL Pinning?

SSL Pinning validates that the server's SSL certificate matches a known public key hash. This prevents:

- **Man-in-the-Middle (MITM) attacks**: Even with valid certificates
- **Certificate authority compromise**: Don't rely solely on CA trust
- **Network interceptors**: Corporate proxies, debugging tools, malicious actors

### Configuration

**Location**: `Sources/Harbor/Request/HURLSessionDelegate.swift`

SSL Pinning uses SHA256 hashes of the certificate's **SubjectPublicKeyInfo (SPKI)**, base64 encoded: `base64(SHA256(SPKI))`. Supported key types: RSA 2048/4096, EC P-256/P-384.

### Getting Public Key Hash

#### Method 1: Using Harbor

```swift
// Compute the pin from any SecCertificate (e.g. extracted from a P12 or a server trust)
if let pin = await Harbor.computePin(for: certificate) {
    await Harbor.setSSlPinningKeys([pin])
}
```

#### Method 2: Using OpenSSL

```bash
# Get certificate from server
openssl s_client -connect api.example.com:443 -showcerts < /dev/null | \
  openssl x509 -outform DER > certificate.der

# Extract public key
openssl x509 -inform DER -in certificate.der -pubkey -noout > publickey.pem

# Generate SHA256 hash of the SPKI
openssl pkey -pubin -in publickey.pem -outform DER | \
  openssl dgst -sha256 -binary | \
  base64
```

#### Method 3: Using Browser

1. Visit the site in a browser (Chrome, Safari)
2. View certificate details
3. Export certificate
4. Use OpenSSL commands above

> **Note**: Pins must be valid base64-encoded SHA-256 hashes (32 bytes, 44 chars with `=` padding or 43 without). Malformed pins log a warning when calling `setSSlPinningKeys` and are ignored during validation.

### Setting Up SSL Pinning

#### Single Key

```swift
// In app initialization
let publicKeyHash = "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg="
await Harbor.setSSlPinningKeys([publicKeyHash])
```

#### Multiple Keys (Recommended)

Pin multiple keys for:
- **Certificate rotation**: Old and new certificates
- **Backup certificates**: Primary and backup servers
- **Key rollover**: Gradual migration

```swift
let primaryKey = "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg="
let backupKey = "GNKGcGj1ue3yRYvqr9t/lz2nkzMU5VZK3QBILcvPJ8U="
let rotationKey = "X2aKNRD8aZ4hJ+5tT6uAzYa1WePqC4p7k9mKp2kYvHg="

await Harbor.setSSlPinningKeys([primaryKey, backupKey, rotationKey])
```

### How SSL Pinning Works

**Validation Process:**

```
Server Connection
    │
    ▼
Extract Server Certificate
    │
    ▼
Extract Public Key from Certificate
    │
    ▼
Rebuild SPKI (SubjectPublicKeyInfo) and Generate SHA256 Hash
    │
    ▼
Compare Hash with Pinned Keys
    │
    ├─ Match Found → Connection Allowed
    │
    └─ No Match → Connection Rejected
                 → Error: .api(statusCode: -1, data: Data())
```

**Implementation**: `Sources/Harbor/Request/HURLSessionDelegate.swift`

```swift
func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
) {
    // Extract server certificate
    // Generate SHA256 hash of public key
    // Compare with pinned keys
    // Accept or reject connection
}
```

### Example: Complete Setup

```swift
import Harbor

class AppConfiguration {
    static func configure() {
        Task {
            // Configure SSL Pinning
            let apiKeys = [
                // Production server
                "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=",
                // Backup server
                "GNKGcGj1ue3yRYvqr9t/lz2nkzMU5VZK3QBILcvPJ8U=",
                // Next rotation (valid from Jan 2027)
                "X2aKNRD8aZ4hJ+5tT6uAzYa1WePqC4p7k9mKp2kYvHg="
            ]
            await Harbor.setSSlPinningKeys(apiKeys)
            
            print("SSL Pinning configured with \(apiKeys.count) keys")
        }
    }
}
```

### Testing SSL Pinning

```swift
// Test with correct key
struct SecureRequest: HGetRequestProtocol {
    typealias Model = Data
    let url = "https://api.example.com/test"
}

let response = await SecureRequest().request()
switch response {
case .success:
    print("SSL Pinning validated successfully")
case .error(let error):
    print("SSL Pinning failed: \(error)")
}
```

### SSL Pinning Best Practices

1. **Pin Multiple Keys**
```swift
// Pin current + future certificates
await Harbor.setSSlPinningKeys([
    currentCertHash,
    nextCertHash,
    backupCertHash
])
```

2. **Plan for Rotation**
```swift
// Add new key before old expires
// Keep old key during transition period
// Remove old key after full migration
```

3. **Remote Configuration**
```swift
// Load pinned keys from remote config (for updates without app release)
struct PinningConfig: Codable {
    let keys: [String]
    let effectiveDate: Date
}

// Fetch and update
if let config = await fetchPinningConfig() {
    await Harbor.setSSlPinningKeys(config.keys)
}
```

4. **Disable in Debug Builds**
```swift
#if DEBUG
// Allow network debugging tools in development
// await Harbor.setSSlPinningKeys([])
#else
// Enable pinning in production
await Harbor.setSSlPinningKeys(productionKeys)
#endif
```

5. **Monitor Expiration**
```swift
// Track certificate expiration dates
// Alert before certificates expire
// Plan rotation 30-60 days in advance
```

### Troubleshooting SSL Pinning

**Connection Rejected:**
```
Error: serverError(statusCode: -1)
```

**Possible causes:**
1. **Wrong hash**: Regenerate hash from current certificate
2. **Certificate rotated**: Server certificate changed
3. **MITM proxy**: Corporate proxy intercepting traffic
4. **Test environment**: Using different certificate than production

**Solutions:**
```swift
// Log actual server certificate hash
// Compare with pinned hashes
// Update pinned keys if certificate legitimately changed
```

## Sensitive Data in Debug Logs

Debug logs (`HDebugRequestProtocol`) redact sensitive headers — `Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `Proxy-Authorization` — both in the generated cURL command and in the structured request log (`headerParameters`), printing `<redacted>` instead of the real value. Cookies are redacted as well.

```swift
// Print real values (only for advanced debugging, never in production)
await Harbor.setLogSensitiveHeaders(true)
```

## Authentication

### Authentication Provider Protocol

**Location**: `Sources/Harbor/Auth/HAuthProviderProtocol.swift`

```swift
protocol HAuthProviderProtocol: Sendable {
    func getAuthorizationHeader() async -> HAuthorizationHeader
    func authFailed() async
}

struct HAuthorizationHeader: Sendable, Equatable {
    let key: String    // e.g. "Authorization", "X-API-Key"
    let value: String  // e.g. "Bearer token123"
}
```

Harbor calls `getAuthorizationHeader()` before every request with `needsAuth = true` and sets the returned key-value pair as a header. On a 401 response, Harbor asks for the header again: if the value changed (e.g. the provider refreshed its token), the request is retried automatically; otherwise `authFailed()` is called and the request fails with `.authNeeded`. There is no built-in expiration check — return the freshest header you have from `getAuthorizationHeader()` and use `authFailed()` to trigger re-authentication.

### Implementing Auth Provider

#### Basic Token Auth

```swift
final class TokenAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    private var accessToken: String?

    func getAuthorizationHeader() async -> HAuthorizationHeader {
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(accessToken ?? "")")
    }

    func authFailed() async {
        // Called when the server rejects the credentials (401 and the header did not change).
        // Refresh the token or ask the user to log in again.
        await refreshToken()
    }

    func setToken(_ token: String) {
        self.accessToken = token
    }

    private func refreshToken() async {
        // Call refresh token endpoint and update accessToken
    }
}
```

#### OAuth2 Auth Provider

```swift
final class OAuth2AuthProvider: HAuthProviderProtocol, @unchecked Sendable {
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

    func getAuthorizationHeader() async -> HAuthorizationHeader {
        // Refresh proactively when the token is about to expire
        if isTokenExpired() {
            try? await refreshTokens()
        }
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(accessToken ?? "")")
    }

    func authFailed() async {
        // The server rejected the current token - force a refresh so the
        // next request picks up new credentials
        try? await refreshTokens()
    }

    private func isTokenExpired() -> Bool {
        guard let expiration = tokenExpiration else {
            return true
        }
        // Consider expired 60 seconds before the actual expiration
        return Date().addingTimeInterval(60) > expiration
    }

    private func refreshTokens() async throws {
        guard let refreshToken = refreshToken else {
            throw AuthError.noRefreshToken
        }

        // Call OAuth2 token refresh endpoint
        let request = RefreshTokenRequest(
            clientId: clientId,
            clientSecret: clientSecret,
            refreshToken: refreshToken
        )

        let response = await request.request()
        switch response {
        case .success(let tokenResponse):
            self.accessToken = tokenResponse.accessToken
            self.refreshToken = tokenResponse.refreshToken
            self.tokenExpiration = Date().addingTimeInterval(tokenResponse.expiresIn)
        case .error(let error):
            throw error
        }
    }

    func setTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        self.accessToken = access
        self.refreshToken = refresh
        self.tokenExpiration = Date().addingTimeInterval(expiresIn)
    }
}

enum AuthError: Error {
    case noRefreshToken
    case refreshFailed
}
```

#### API Key Auth Provider

```swift
final class APIKeyAuthProvider: HAuthProviderProtocol, @unchecked Sendable {
    private let apiKey: String
    private let headerName: String

    init(apiKey: String, headerName: String = "X-API-Key") {
        self.apiKey = apiKey
        self.headerName = headerName
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader {
        HAuthorizationHeader(key: headerName, value: apiKey)
    }

    func authFailed() async {
        // API keys can't be refreshed - prompt for a new key if needed
    }
}
```

### Setting Auth Provider

```swift
// Configure once at app startup
let authProvider = OAuth2AuthProvider(
    clientId: "your-client-id",
    clientSecret: "your-client-secret",
    tokenEndpoint: "https://auth.example.com/token"
)

await Harbor.setAuthProvider(authProvider)
```

### Using Authentication in Requests

```swift
struct GetUserProfileRequest: HGetRequestProtocol {
    typealias Model = UserProfile
    let url = "https://api.example.com/profile"
    let needsAuth: Bool = true  // Will automatically add auth headers
}
```

### Authentication Flow

```
Request with needsAuth = true
    │
    ▼
Check if auth provider is set
    │
    ├─ No → Return authProviderNeeded error
    │
    └─ Yes
        │
        ▼
    Call getAuthorizationHeader() → Add header → Execute request
        │
        ▼
Request completes
    │
    ├─ Status 200-299 → Return success
    │
    └─ Status 401
        │
        ▼
    Call getAuthorizationHeader() again
        │
        ├─ Header changed (provider refreshed credentials)
        │   → Retry request once with the new header
        │
        └─ Header unchanged
            → Call authFailed() → Return authNeeded error
```

### Complete Example

```swift
// 1. Create auth provider
let authProvider = OAuth2AuthProvider(
    clientId: "app-client-id",
    clientSecret: "app-secret",
    tokenEndpoint: "https://auth.example.com/oauth/token"
)

// 2. Login and set tokens
func login(email: String, password: String) async throws {
    let loginRequest = LoginRequest(email: email, password: password)
    let response = await loginRequest.request()
    
    switch response {
    case .success(let tokens):
        await authProvider.setTokens(
            access: tokens.accessToken,
            refresh: tokens.refreshToken,
            expiresIn: tokens.expiresIn
        )
        await Harbor.setAuthProvider(authProvider)
    case .error(let error):
        throw error
    }
}

// 3. Make authenticated requests
struct GetUserDataRequest: HGetRequestProtocol {
    typealias Model = UserData
    let url = "https://api.example.com/user/data"
    let needsAuth = true  // Auth headers added automatically
}

let response = await GetUserDataRequest().request()
// If token expired, Harbor automatically refreshes and retries
```

### Authentication Best Practices

1. **Store Tokens Securely**
```swift
// Use Keychain for token storage
KeychainManager.save(token: accessToken, key: "access_token")
let token = KeychainManager.load(key: "access_token")
```

2. **Handle Auth Errors**
```swift
let response = await request.request()
switch response {
case .error(.authNeeded):
    // Token refresh failed - re-authenticate user
    await showLoginScreen()
default:
    break
}
```

3. **Preemptive Token Refresh**
```swift
// Refresh the token inside getAuthorizationHeader() when it is close to expiring,
// so Harbor always gets a valid header
func getAuthorizationHeader() async -> HAuthorizationHeader {
    if tokenIsCloseToExpiring {
        try? await refreshTokens()
    }
    return HAuthorizationHeader(key: "Authorization", value: "Bearer \(accessToken ?? "")")
}
```

4. **Clear Auth on Logout**
```swift
func logout() async {
    await Harbor.setAuthProvider(nil)
    await Harbor.clearAllCache()
    // Clear stored tokens
}
```

## Combining Security Features

### mTLS + SSL Pinning + Auth

```swift
func configureFullSecurity() async {
    // 1. Configure mTLS
    guard let certUrl = Bundle.main.url(forResource: "client", withExtension: "p12") else {
        return
    }
    let mtls = HmTLS(p12FileUrl: certUrl, password: getSecurePassword())
    await Harbor.setMTLS(mtls)
    
    // 2. Configure SSL Pinning
    let pinnedKeys = [
        "YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=",
        "GNKGcGj1ue3yRYvqr9t/lz2nkzMU5VZK3QBILcvPJ8U="
    ]
    await Harbor.setSSlPinningKeys(pinnedKeys)
    
    // 3. Configure Authentication
    let authProvider = OAuth2AuthProvider(
        clientId: "client-id",
        clientSecret: "client-secret",
        tokenEndpoint: "https://auth.example.com/token"
    )
    await Harbor.setAuthProvider(authProvider)
    
    print("Full security configured: mTLS + SSL Pinning + Auth")
}
```

## Security Testing

### Test mTLS

```swift
func testMTLS() async {
    struct MTLSTest: HGetRequestProtocol {
        typealias Model = MTLSResponse
        let url = "https://certauth.cryptomix.com/json"
    }
    
    let response = await MTLSTest().request()
    XCTAssertTrue(response.isSuccess)
}
```

### Test SSL Pinning

```swift
func testSSLPinning() async {
    // Test with correct key
    await Harbor.setSSlPinningKeys(["correct-hash"])
    let response1 = await SecureRequest().request()
    XCTAssertTrue(response1.isSuccess)
    
    // Test with wrong key (should fail)
    await Harbor.setSSlPinningKeys(["wrong-hash"])
    let response2 = await SecureRequest().request()
    XCTAssertTrue(response2.isError)
}
```

### Test Authentication

```swift
func testAuthentication() async {
    let mockAuth = MockAuthProvider(token: "test-token")
    await Harbor.setAuthProvider(mockAuth)
    
    struct AuthRequest: HGetRequestProtocol {
        typealias Model = Data
        let url = "https://api.example.com/private"
        let needsAuth = true
    }
    
    let response = await AuthRequest().request()
    XCTAssertTrue(response.isSuccess)
}
```

## Related Files

**Security Implementation:**
- `Sources/Harbor/Request/HmTLS.swift` - mTLS configuration
- `Sources/Harbor/Request/HURLSessionDelegate.swift` - SSL Pinning
- `Sources/Harbor/Auth/HAuthProviderProtocol.swift` - Authentication
- `Sources/Harbor/Utils/PKCS12.swift` - Certificate loading
- `Sources/Harbor/Utils/HSPKI.swift` - SPKI extraction and pin computation/validation
- `Sources/Harbor/Utils/SHA256.swift` - Hash utilities

**Examples:**
- `Example/HarborExample/RequestsView.swift` - mTLS setup example
- `Example/HarborExample/Requests/MTLSRequest.swift` - mTLS request
- `Tests/HarborTests/HarborSecurityTests.swift` - Security tests
