# Harbor JSON-RPC Examples

`HarborJRPC` sends JSON-RPC 2.0 calls (single, notification, batch) through Harbor's pipeline: auth provider, retry policy, transport security, logging and custom session. Every call is an HTTP `POST`.

```swift
import HarborJRPC
```

## Setup

```swift
func configureRPC() async {
    // Endpoint and protocol version (jrpcVersion defaults to "2.0")
    await HarborJRPC.configure(url: URL(string: "https://rpc.example.com")!, jrpcVersion: "2.0")

    // Network settings (timeouts, auth, pinning, mTLS, logging) come from Harbor
    await Harbor.setDefaultTimeoutInterval(20)
}
```

For single calls (`request()` / `requestResult()`), the `jsonrpc` member of the response must equal the configured version, otherwise the call fails with `.invalidResponse`; notifications and batches don't check it. A request can target another endpoint without changing the global URL through `endpoint: URL?`.

## The protocol

```swift
struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String                       // decoded from `result`
    let method = "eth_getBalance"
    let parameters: HJRPCParams?                   // .positioned([...]) or .named([...])

    init(address: String, block: String = "latest") {
        parameters = .positioned([address, block])
    }
}
```

| Requirement | Default |
|---|---|
| `Model: HModel`, `method: String` | required |
| `parameters: HJRPCParams?` | `nil` (no `params` member) |
| `needsAuth: Bool` | `false` |
| `retryPolicy: HRetryPolicy?` | `nil` |
| `headerParameters: [String: String]?` | `nil` |
| `isNotification: Bool` | `false` |
| `requestID: HJRPCId?` | `nil`: a UUID string id is generated |
| `endpoint: URL?` | `nil`: the configured URL |

Parameters accept any `Encodable & Sendable` value, including nested structs and big integers. Values JSON can't represent (`Double.nan`, `.infinity`) make the call fail with `.codable` instead of sending `null`.

## Calling

```swift
func balance() async {
    // Throwing form
    do {
        let wei = try await GetBalanceRequest(address: "0xabc").request()
        print(wei)
    } catch let error as HJRPCRequestError {
        print(error.localizedDescription)
    } catch {
        print(error)
    }

    // Non-throwing form
    switch await GetBalanceRequest(address: "0xabc").requestResult() {
    case .success(let wei):
        print(wei)
    case .error(let error):
        print(error)
    }
}
```

## Ethereum examples

```swift
struct BlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
}

struct Transaction: Codable, Sendable {
    let hash: String
    let from: String
    let to: String?
    let value: String
}

struct TransactionByHashRequest: HJRPCRequestProtocol {
    typealias Model = Transaction?                 // `result: null` decodes as nil
    let method = "eth_getTransactionByHash"
    let parameters: HJRPCParams?

    init(hash: String) {
        parameters = .positioned([hash])
    }
}

struct CallParameters: Encodable, Sendable {
    let to: String
    let data: String
}

struct EthCallRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_call"
    let parameters: HJRPCParams?
    // eth_call is read-only: allow retries after timeouts / retryable statuses even though it is a POST
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 3, retryNonIdempotentRequests: true)

    init(to: String, data: String) {
        parameters = .positioned([CallParameters(to: to, data: data), "latest"])
    }
}

struct SendRawTransactionRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_sendRawTransaction"
    let parameters: HJRPCParams?
    // A write: keep the default (retried only when the request never reached the server)
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2)

    init(signedTransaction: String) {
        parameters = .positioned([signedTransaction])
    }
}

struct PolygonBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
    let endpoint: URL? = URL(string: "https://polygon-rpc.example.com")
}
```

Because JSON-RPC calls are `POST`, a plain `HRetryPolicy(maxRetries:)` retries only failures that happened before the request reached the server (DNS failure, connection refused, offline). Set `retryNonIdempotentRequests: true` for read-only methods so timeouts and statuses such as 429, 502 and 503 are retried too.

## Named parameters (Bitcoin-style)

```swift
struct BlockHashRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "getblockhash"
    let parameters: HJRPCParams?

    init(height: Int) {
        parameters = .named(["height": height])
    }
}

struct AuthenticatedNodeRequest: HJRPCRequestProtocol {
    typealias Model = Int
    let method = "getblockcount"
    let headerParameters: [String: String]? = ["Authorization": "Basic dXNlcjpwYXNz"]
}
```

## Generic results with `HJSONValue`

```swift
struct RawRequest: HJRPCRequestProtocol {
    typealias Model = HJSONValue
    let method: String
    let parameters: HJRPCParams?
}

func inspect() async throws {
    let value = try await RawRequest(method: "net_version", parameters: nil).request()
    switch value {
    case .string(let version):
        print(version)
    case .int(let number):
        print(number)
    case .decimal(let big):                         // integers beyond Int (e.g. UInt64.max)
        print(big)
    case .object(let fields):
        print(fields.keys)
    default:
        print(value)
    }
}
```

`.decimal` keeps the digits of an integer beyond `Int` exact on iOS 18 / macOS 15 and later (swift-foundation `JSONDecoder`). On earlier OS versions such integers may be rounded through `Double` before reaching `Decimal`. The same applies to big integers passed in `HJRPCParams`.

## Notifications

```swift
struct LogEventNotification: HJRPCRequestProtocol {
    typealias Model = HJSONValue
    let method = "log_event"
    let isNotification = true                     // no `id`; the server must not answer
    let parameters: HJRPCParams? = .named(["event": "app_open"])
}

func sendNotification() async throws {
    try await LogEventNotification().notify()
}
```

`notify()` throws `HJRPCRequestError.invalidRequest` when `isNotification` is `false` (the only case that produces it). A 2xx response with an empty body counts as delivered. A 2xx body that isn't JSON-RPC throws `.codable`, and a JSON-RPC error object throws `.jrpcError`.

## Batches

```swift
func batch() async throws {
    let responses = try await HarborJRPC.batch([
        BlockNumberRequest(),
        GetBalanceRequest(address: "0xabc"),
        LogEventNotification()                    // notifications produce no element
    ])

    for response in responses {
        switch response {
        case .success(let id, let result):
            print(id?.description ?? "-", result)
        case .error(let id, let error):
            print(id?.description ?? "-", error)
        }
    }

    // Decode an element's HJSONValue into a model
    if case .success(_, let result)? = responses.first {
        let data = try JSONEncoder().encode(result)
        let blockNumber = try JSONDecoder().decode(String.self, from: data)
        print(blockNumber)
    }

    let nothing = try await HarborJRPC.batch([])  // [] with no network call
    print(nothing.isEmpty)
}
```

- `HarborJRPC.batch(_:)` is `async throws`. It throws when the batch as a whole fails: no endpoint, mixed endpoints (`.malformedRequest`), encoding, transport or HTTP errors, a body that isn't a batch response, or a single error object rejecting the batch (`.jrpcError`).
- Responses are paired by the `id` the server echoes. Servers may reorder or omit them.
- Merge rules: all requests must resolve to the same endpoint. Headers are merged (the first request setting a header wins). The batch is authenticated if any request has `needsAuth`. It is logged if any request conforms to `HDebugRequestProtocol`. The first non-nil `retryPolicy` is used, but its `retryNonIdempotentRequests` is kept only if **every** request opts in.

## Errors

```swift
func handle(_ error: HJRPCRequestError) {
    switch error {
    case .jrpcError(let rpcError):
        // Also returned for 4xx/5xx responses whose body is a JSON-RPC error object
        print(rpcError.code, rpcError.message, rpcError.data as Any, rpcError.httpStatusCode as Any)
        if rpcError.standardCode == .methodNotFound { print("Unknown method") }
        if rpcError.isServerError { print("Implementation-defined server error") }
    case .api(let statusCode, _):
        print("HTTP \(statusCode) without a JSON-RPC error body")
    case .idMismatch(let expected, let actual):
        print("id mismatch", expected as Any, actual as Any)
    case .invalidResponse:
        print("Not a JSON-RPC response (or wrong jsonrpc version)")
    case .urlNeeded:
        print("Call HarborJRPC.configure(url:) first")
    case .noConnection, .timeout, .cannotFindHost, .cannotConnectToHost, .networkFailure:
        print("Network problem")
    case .certificate:
        print("TLS / pinning failure")
    case .authNeeded, .authProviderNeeded:
        print("Auth problem")
    case .codable(let model, let underlying):
        print("Coding error in \(model): \(underlying)")
    case .malformedRequest, .invalidRequest, .invalidHttpResponse, .cancelled, .unknown:
        print(error.localizedDescription)
    }
}
```

Standard codes (`HJRPCStandardCode`): `.parseError` (-32700), `.invalidRequest` (-32600), `.methodNotFound` (-32601), `.invalidParams` (-32602) and `.internalError` (-32603). The server error range is -32099...-32000 (`isServerError`).

## Debug logging

```swift
struct DebugBlockNumberRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
    let debugType: HDebugRequestType = .requestAndResponse
}
```

## SwiftUI polling

```swift
@MainActor
final class BlockViewModel: ObservableObject {
    @Published var blockNumber = "-"

    func poll() async {
        while !Task.isCancelled {
            if let block = try? await BlockNumberRequest().request() {
                blockNumber = block
            }
            try? await Task.sleep(nanoseconds: 12_000_000_000)
        }
    }
}

struct BlockView: View {
    @StateObject private var model = BlockViewModel()

    var body: some View {
        Text("Block \(model.blockNumber)")
            .task { await model.poll() }   // cancelled when the view disappears
    }
}
```

## Testing

`HMock` can't target JSON-RPC requests, because they are sent through internal wrapper types. Stub the transport with a `URLProtocol` on a custom session and give the request a fixed `requestID` so the stubbed response `id` matches. See `../testing.md`.

```swift
struct FixedIDBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method = "eth_blockNumber"
    let requestID: HJRPCId? = .string("1")
}
```

## Related files

- `Sources/HarborJRPC/HarborJRPC.swift`: configuration and `batch`.
- `Sources/HarborJRPC/Request/HJRPCRequestProtocol.swift`, `HJRPCRequestManager.swift`.
- `Sources/HarborJRPC/Request/HJRPCRequestError.swift`, `HJRPCError.swift`, `HJSONValue.swift`, `HJRPCId.swift`.
