# Harbor Logging and Redaction

Debug output is opt-in per request and redacted by default. It works the same for REST requests, JSON-RPC calls and WebSocket connections.

## Turning it on

```swift
struct DebugUserRequest: HGetRequestProtocol, HDebugRequestProtocol {
    typealias Model = String
    let url = "https://api.example.com/me"
    let debugType: HDebugRequestType = .requestAndResponse   // also the default
}

func enableLogs() async {
    await Harbor.setLoggingEnabled(true)   // default: on in DEBUG, off in release; works in release builds too
}
```

- Output requires both: the request conforms to `HDebugRequestProtocol` and logging is enabled.
- `debugType: HDebugRequestType` is `.none`, `.request`, `.response` or `.requestAndResponse` (the default).
- Security warnings (malformed pins, a custom session that bypasses pinning or mTLS, ...) are logged regardless of these settings.
- Harbor logs through [LogBird](https://github.com/javiermanzo/LogBird); apps don't need to import it.

What is logged:

| Product | `.request` | `.response` |
|---|---|---|
| REST | method, URL, headers, body and a cURL command | status, headers, body and duration |
| JSON-RPC | the HTTP request with the JSON-RPC envelope as its body | the HTTP response |
| WebSocket | the handshake (URL and headers) and sent messages | the open event, received messages and the close |

Errors are logged whatever the `debugType` (`.none` included), as long as logging is enabled. WebSocket message payloads are redacted like response bodies and truncated at 16 K characters.

## Redaction

Everything Harbor prints goes through one redaction policy (`HRedactionPolicy`): request and response headers, query values, path, query and body parameters, cURL commands, response bodies, WebSocket subprotocols and messages, and `HRequestError.api` descriptions. In logged URLs, the user info (`user:password@`) is always replaced, and the values of sensitive query items, fragment items (`#access_token=...`) and path parameters are redacted. A key is sensitive when its normalized form (lowercased, `-`, `_` and spaces removed) contains:

- a built-in credential key (`authorization`, `cookie`, `set-cookie`, `x-api-key`, `password`, `token`, `secret`, `session_id`, `sec-websocket-protocol`, ...), which always applies;
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

The cURL command of a REST log includes the stored cookies (redacted by default) only when the session actually sends them; an explicit `Cookie` header is printed otherwise. JSON-RPC logs name the app's request type and method.

Error descriptions never include an error's `userInfo`, where `URLSession` puts the failing URL and its query.

## Related files

- `Sources/HarborCore/Debug/HDebugRequestProtocol.swift`, `HLogger.swift` (the facade over LogBird), `HRedactionPolicy.swift`, `HJSONRedactor.swift`, `HLoggingSensitiveKeyAction.swift`.
- `Sources/Harbor/Debug/HDebugRequestProtocol+Request.swift`: REST request/response and cURL output.
- `Sources/HarborWebSocket/Debug/HWebSocketLogContext.swift`: WebSocket output.
