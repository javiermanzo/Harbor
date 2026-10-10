# Harbor Security

Covers SSL pinning, mutual TLS, redirects, custom sessions, authentication and log redaction.

## SSL pinning

Pins are `base64(SHA256(SubjectPublicKeyInfo))`, the same format as HPKP/TrustKit/OkHttp. Raw-key hashes from Harbor v3 no longer match.

Generate a pin:

```bash
openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | openssl base64
```

Or in Swift:

```swift
func pin(for certificateDER: Data) async -> String? {
    guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else { return nil }
    return await Harbor.computePin(for: certificate)   // nil for unsupported key types
}
```

Supported keys: RSA of any size, and EC on P-256, P-384 and P-521.

Configure pins:

```swift
func configurePinning() async {
    // Global pins (every host). Include a backup pin for key rotation.
    await Harbor.setSSLPinningKeys(["PRIMARY_PIN_BASE64=", "BACKUP_PIN_BASE64="])

    // Host-scoped pins take precedence over the global ones for those hosts.
    await Harbor.setSSLPinningKeys(["API_PIN_BASE64="], forHosts: ["api.example.com"])

    // Remove pins
    await Harbor.setSSLPinningKeys(nil, forHosts: ["api.example.com"])
    await Harbor.setSSLPinningKeys(nil)
}
```

How it works (`HURLSessionDelegate`):

1. Pins are looked up by the challenge host: host-scoped pins first, then global pins. Hosts are normalized (lowercased, trailing dot removed). If no pins apply, the system's default handling runs.
2. The server trust is evaluated first, off the session's delegate queue. An untrusted chain is rejected even if a pin would match.
3. The SPKI hash of every certificate in the chain (leaf, intermediates, root) is compared with the pins. One match accepts the connection. Certificates with unsupported key types are skipped, with one warning per host.
4. On a mismatch or an untrusted chain, the challenge is cancelled and the request fails with `HRequestError.certificate`. It is never retried and never served from cache.

Malformed pins (not base64 SHA-256) trigger a security warning when set and are ignored. If only malformed pins are configured for a host, every connection to it fails.

Only certificate-specific failures surface as `HRequestError.certificate`: a pin mismatch, an untrusted chain, an mTLS rejection and the certificate `URLError` codes (`serverCertificateUntrusted`, `serverCertificateHasBadDate`, `serverCertificateHasUnknownRoot`, `serverCertificateNotYetValid`, `clientCertificateRejected`, `clientCertificateRequired`). A generic `URLError.secureConnectionFailed` maps to `.networkFailure` and is retried as a transient failure for idempotent (or opted-in) requests.

## Mutual TLS

```swift
func configureMTLS() async {
    guard let p12URL = Bundle.main.url(forResource: "client", withExtension: "p12") else { return }

    let mTLS = HMTLS(p12FileUrl: p12URL, hosts: ["api.example.com"]) {
        // async throws: read from the keychain, a vault, a biometric prompt...
        "p12-password"
    }

    do {
        try await Harbor.setMTLS(mTLS)
    } catch let error as HMTLSError {
        // .fileNotFound, .passwordProviderFailed, .invalidPassword, .invalidP12Format, .noIdentity
        print(error)
    } catch {
        print(error)
    }

    // Later:
    await Harbor.clearMTLS()
}
```

- The password provider is called once, during import, and the password isn't retained. `HMTLS(p12FileUrl:hosts:passwordProvider:)` is the only initializer.
- The P12 is read and imported off the actor. The identity is imported into memory only (`kSecImportToMemoryOnly`) on iOS and on macOS 15 and later. On macOS 14, `SecPKCS12Import` has no in-memory option and persists the key and certificates to the default (login) keychain.
- The identity and its certificate chain are presented only to the `hosts` you list (case-insensitive). With `hosts: nil` they go to every host that asks for a client certificate, so scoping is recommended. Other hosts get default handling.
- On failure, mTLS stays disabled and the error is thrown.

## Redirects

When a redirect leaves the original origin (scheme, host or port; default ports made explicit), Harbor's delegate strips the auth provider's header key, `Authorization`, `Cookie`, `Proxy-Authorization`, `Set-Cookie` and `X-API-Key` from the new request. Same-origin redirects are followed unchanged.

## Custom URLSession

`Harbor.setCustomURLSession(_:)` uses the session as-is. Pinning, mTLS and redirect stripping are enforced only when the session's delegate is Harbor's:

```swift
func secureCustomSession() async {
    // 1. Configure pins / mTLS first: the delegate captures the configuration now.
    await Harbor.setSSLPinningKeys(["API_PIN_BASE64="], forHosts: ["api.example.com"])

    // 2. Build the session with Harbor's delegate.
    let configuration = URLSessionConfiguration.default
    configuration.waitsForConnectivity = true
    let delegate = await Harbor.makeURLSessionDelegate()
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    await Harbor.setCustomURLSession(session)
}
```

If you need your own delegate, forward its calls to an `HURLSessionDelegate`:

```swift
final class AppSessionDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let harbor: HURLSessionDelegate

    init(harbor: HURLSessionDelegate) {
        self.harbor = harbor
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        harbor.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        harbor.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
    }
}
```

A session-level challenge handler can call `harbor.handleChallenge(challenge, task: nil, completionHandler:)`. Harbor logs a security warning, even with logging disabled, when pins or mTLS are configured and the custom session doesn't use its delegate, or when pins or mTLS change while a custom session holds an older delegate. In the second case, build a new delegate and session. `setDefaultResourceTimeoutInterval(_:)` doesn't apply to custom sessions. The per-request timeout does, because it is set on each `URLRequest`.

## Authentication

```swift
actor TokenStore {
    private(set) var accessToken: String?
    func update(_ token: String?) { accessToken = token }
}

final class OAuthProvider: HAuthProviderProtocol {
    let store: TokenStore

    init(store: TokenStore) {
        self.store = store
    }

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        guard let token = await store.accessToken else { return nil }   // nil: send without credentials
        return HAuthorizationHeader(key: "Authorization", value: "Bearer \(token)")
    }

    func authFailed() async {
        // Refresh the token (or log out). Called at most once per request; concurrent
        // requests rejected with the same header share one call. Not called when
        // getAuthorizationHeader() already returns a header different from the rejected one.
        await store.update("refreshed-token")
    }
}

struct AccountRequest: HGetRequestProtocol {
    typealias Model = String
    let url = "https://api.example.com/account"
    let needsAuth = true
}

func authFlow() async {
    let store = TokenStore()
    await Harbor.setAuthProvider(OAuthProvider(store: store))
    _ = await AccountRequest().request()

    // Logout
    await store.update(nil)
    await Harbor.setAuthProvider(nil)
    await Harbor.clearAllCache()   // cached responses are per credential but are not deleted automatically
}
```

Flow:

- A request with `needsAuth == false` never consults the provider. With `needsAuth == true` and no provider, it fails with `.authProviderNeeded`.
- The header is applied to the built `URLRequest`. Your request value is never mutated.
- On a 401, Harbor asks the provider for its current header (`getAuthorizationHeader()` is called at most twice per request: once to detect a rotated header and, only after `authFailed()`, once more for the refreshed one). If it already differs from the rejected one (a refresh finished meanwhile), the request is re-sent with it without calling `authFailed()`. Otherwise Harbor calls `authFailed()` exactly once per request (concurrent requests rejected with the same header share one call), fetches the header again, and re-sends the request once if it changed. When no re-send is possible, or the re-sent request is rejected again, the error is `.authNeeded`; a request that ends in `.authNeeded` after a 401 has always triggered `authFailed()`, and never more than once. A 401 on a request that doesn't need auth is `.authNeeded` without calling the provider. These extra attempts are separate from `retryPolicy.maxRetries`.

## Log redaction

Debug output is opt-in per request (`HDebugRequestProtocol`) and gated by `Harbor.setLoggingEnabled(_:)` (default: on in DEBUG, off in release; it works in release builds when enabled). Security warnings are logged regardless of that setting.

Everything Harbor prints goes through one redaction policy (`HRedactionPolicy`): request and response headers, query values, path, query and body parameters, cURL commands, response bodies and `HRequestError.api` descriptions. A key is sensitive when its normalized form (lowercased, `-`, `_` and spaces removed) contains:

- a built-in credential key (`authorization`, `cookie`, `set-cookie`, `x-api-key`, `password`, `token`, `secret`, `session_id`, ...), which always applies;
- a configurable key, managed with `Harbor.updateLogSensitiveKeys(_:)`;
- the header key the auth provider's credential was sent under.

```swift
func configureRedaction() async {
    await Harbor.updateLogSensitiveKeys(.add(["otp", "pin_code"]))  // extend
    await Harbor.updateLogSensitiveKeys(.set(["otp"]))              // replace the configurable set
    await Harbor.updateLogSensitiveKeys(.reset)                     // defaults
    await Harbor.updateLogSensitiveKeys(.clear)                     // only the built-in floor remains
    await Harbor.setLogSensitiveValues(true)                        // print everything unredacted (local debugging only)
    await Harbor.setLogSensitiveValues(false)                       // default: redact as <redacted>
}
```

## Checklist

- Pin with at least one backup pin, and scope pins to the hosts you control.
- Scope the mTLS identity with `hosts:`. Load the password lazily.
- Use `Harbor.makeURLSessionDelegate()` for any custom session, and rebuild it after changing pins or mTLS.
- Call `Harbor.clearAllCache()` on logout.
- Keep `setLogSensitiveValues(false)` outside local debugging.

## Related files

- `Sources/Harbor/Request/HURLSessionDelegate.swift`: challenges, pin matching, redirects.
- `Sources/Harbor/Utils/HSPKI.swift`: SPKI reconstruction and pin computation.
- `Sources/Harbor/Request/HmTLS.swift`, `Sources/Harbor/Utils/PKCS12.swift`: mTLS import.
- `Sources/Harbor/Debug/HRedactionPolicy.swift`: log redaction.
- `Sources/Harbor/Auth/HAuthProviderProtocol.swift`.
