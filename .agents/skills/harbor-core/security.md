# Harbor Security

Covers SSL pinning, mutual TLS, redirects and custom sessions. They apply to every product: REST requests, JSON-RPC calls (sent as REST POSTs) and WebSocket handshakes. Authentication: `auth.md`. Log redaction: `logging.md`.

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

Malformed pins (not base64 SHA-256) trigger a security warning when set and are ignored. If only malformed pins are configured for a host, every connection to it fails; an empty pin list (`[]`) rejects every connection too and logs a warning (pass `nil` to stop pinning).

Hosts passed to `setSSLPinningKeys(_:forHosts:)` are trimmed, lowercased and stripped of a trailing dot. They must be bare host names as `URLProtectionSpace.host` reports them, and match exactly (pin `api.example.com` and `cdn.example.com` separately; subdomains are not included): a value with a scheme, a port or a path (`https://api.example.com`, `api.example.com:443`), spaces inside or non-ASCII characters (use punycode, `xn--bcher-kva.de`) can never match, so it logs a security warning and is skipped. A host without pins of its own falls back to the global pins or, without them, to default handling (no pinning).

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
- The latest call wins: when `setMTLS(_:)` or `clearMTLS()` is called again while an import is running (e.g. a biometric prompt), the earlier `setMTLS(_:)` changes nothing when it finishes and throws `CancellationError`, so a slow import can never reinstall an identity after logout.
- The P12 is read and imported off the actor. The identity is imported into memory only (`kSecImportToMemoryOnly`) on iOS and on macOS 15 and later. On macOS 14, `SecPKCS12Import` has no in-memory option and persists the key and certificates to the default (login) keychain.
- The identity and its certificate chain are presented only to the `hosts` you list (case-insensitive). With `hosts: nil` they go to every host that asks for a client certificate, so scoping is recommended. Other hosts get default handling.
- On failure, mTLS stays disabled and the error is thrown.

## Redirects

When a redirect leaves the original origin (scheme, host or port; default ports made explicit), Harbor's delegate strips the auth provider's header key and every header whose name contains a built-in sensitive key (the same list that drives log redaction: `Authorization`, `Proxy-Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `Api-Key`, any `…Token`, `…Secret`, `…Signature`, `…Credential`, and `Sec-WebSocket-Protocol`, since WebSocket clients often authenticate by offering a token as the subprotocol) from the new request. Same-origin redirects are followed unchanged. WebSocket handshakes go through the same delegate; their debug logs redact subprotocols like any sensitive header.

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

A session-level challenge handler can call `harbor.handleChallenge(challenge, task: nil, completionHandler:)`; without the task, a rejected handshake surfaces as `.cancelled` instead of `.certificate`. Harbor logs a security warning, even with logging disabled, when pins or mTLS are configured and the custom session's delegate is not an `HURLSessionDelegate` (a delegate that forwards to one gets it too: ignore it then), and when the session's `HURLSessionDelegate` was created before the last pin or mTLS change, whether the change came before or after `setCustomURLSession(_:)`. In the second case, build a new delegate and session. `setDefaultResourceTimeoutInterval(_:)` doesn't apply to custom sessions. The per-request timeout does, because it is set on each `URLRequest`.

## Checklist

- Pin with at least one backup pin, and scope pins to the hosts you control.
- Scope the mTLS identity with `hosts:`. Load the password lazily.
- Use `Harbor.makeURLSessionDelegate()` for any custom session, and rebuild it after changing pins or mTLS.
- Call `Harbor.clearAllCache()` on logout (`auth.md`).
- Keep `setLogSensitiveValues(false)` outside local debugging (`logging.md`).

## Related files

- `Sources/HarborCore/Request/HURLSessionDelegate.swift`: challenges, pin matching, redirects.
- `Sources/HarborCore/Utils/HSPKI.swift`: SPKI reconstruction and pin computation.
- `Sources/HarborCore/Request/HMTLS.swift`, `HMTLSIdentity.swift`, `HMTLSError.swift`, `Sources/HarborCore/Utils/PKCS12.swift`: mTLS configuration and import.
