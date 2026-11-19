# Harbor Retry Policy

`HRetryPolicy` is shared by every product: REST requests and JSON-RPC calls retry the whole request, WebSocket connections retry the handshake only. A `nil` `retryPolicy` (the default) means no retries.

```swift
let conservative = HRetryPolicy(maxRetries: 3)                    // 0.3s, 0.6s, 1.2s (+0...0.1s jitter)
let custom = HRetryPolicy(maxRetries: 5,
                          baseDelay: 1,
                          multiplier: 1.5,
                          jitter: 0...0.5,
                          retryableStatusCodes: [429, 503],
                          retryNonIdempotentRequests: false)
let wait = custom.delay(forRetry: 2)                               // backoff before the 2nd retry, capped at maxDelay
```

Defaults: `maxRetries: 0`, `baseDelay: 0.3` (negative values clamp to 0), `multiplier: 2`, `jitter: 0...0.1` (inverted ranges are normalized), `retryableStatusCodes: HRetryPolicy.defaultRetryableStatusCodes`, `retryNonIdempotentRequests: false`.

## What is retried

- Statuses in `retryableStatusCodes` (default `HRetryPolicy.defaultRetryableStatusCodes`: 408, 425, 429, 500, 502, 503, 504).
- `URLError` `.timedOut`, `.networkConnectionLost` and `.secureConnectionFailed`, for idempotent requests (or every request with `retryNonIdempotentRequests`).
- `URLError` `.cannotConnectToHost`, `.cannotFindHost`, `.dnsLookupFailed`, `.notConnectedToInternet`, `.internationalRoamingOff`, `.callIsActive` and `.dataNotAllowed`, for any request, since it never reached the server.

Never retried: other statuses (400, 404, 422, ...), cancellation, certificate errors (pin mismatches, mTLS rejections and certificate-specific `URLError`s), malformed URLs, and errors other than `URLError`.

## Idempotency per product

| Product | Treated as idempotent | Retried only after pre-connection failures (unless `retryNonIdempotentRequests: true`) |
|---|---|---|
| REST | GET, PUT, DELETE | POST, PATCH |
| JSON-RPC | none | every call (all are POST); opt in for read-only methods |
| WebSocket | the handshake | n/a |

## Delays

- The backoff is `baseDelay * multiplier^(retry - 1)` plus a random value from `jitter`, capped at `HRetryPolicy.maxDelay` (60 s). `delay(forRetry:)` (1-based) exposes it, for example to back off between WebSocket reconnections.
- On a 429 or 503, `Retry-After` (delta-seconds or HTTP-date) replaces the backoff. A `Retry-After` longer than `maxDelay` is not waited for: the request fails right away with that status (`.api` for REST, `.handshakeFailed(statusCode:)` for WebSocket).
- Cancelling the calling task ends the wait with `.cancelled`.
- A `401` is handled by the auth flow, outside `maxRetries` (`auth.md`).

Tests: `HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)` avoids real waits.

## Related files

- `Sources/HarborCore/Request/HRetryPolicy.swift`: classification and backoff.
- `Sources/HarborCore/Request/HRequestManager+Retry.swift`: error mapping, `Retry-After` parsing.
- `Sources/HarborCore/Request/HRequestManager+AttemptLoop.swift`: the attempt loop shared by REST and WebSocket.
