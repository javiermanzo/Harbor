# Harbor JSON-RPC Examples

Complete guide to using Harbor's JSON-RPC 2.0 support.

## Overview

HarborJRPC is a separate module that provides JSON-RPC 2.0 support built on top of Harbor's REST functionality.

**Location**: `Sources/HarborJRPC/`

## Basic Setup

### Configure JSON-RPC Endpoint

```swift
// Set the JSON-RPC endpoint once at app startup
await HarborJRPC.setURL(URL(string: "https://ethereum.publicnode.com")!)

// Or from a string, which throws if the URL is invalid
try await HarborJRPC.setURL("https://ethereum.publicnode.com")

// Or configure URL and protocol version in a single call
await HarborJRPC.configure(url: URL(string: "https://ethereum.publicnode.com")!, jrpcVersion: "2.0")
```

Network-level settings (timeout, auth provider, mTLS, mocks, logging) are configured through `Harbor`'s API, the same way as for REST requests.

### Simple JSON-RPC Request

```swift
struct GetBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
}

// Execute
let response = await GetBlockNumberRequest().requestResult()
switch response {
case .success(let blockNumber):
    print("Block number: \(blockNumber)")
case .error(let error):
    print("Error: \(error.localizedDescription)")
}
```

Or with the throwing variant:

```swift
do {
    let blockNumber = try await GetBlockNumberRequest().request()
    print("Block number: \(blockNumber)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

## JSON-RPC Request Protocol

### Protocol Definition

```swift
protocol HJRPCRequestProtocol: Sendable {
    associatedtype Model: HModel  // Codable & Sendable

    var method: String { get }
    var needsAuth: Bool { get }              // default: false
    var retries: Int? { get }                // default: nil
    var headers: [String: String]? { get }   // default: nil
    var parameters: HJRPCParams? { get }     // default: nil
    var isNotification: Bool { get }         // default: false
    var requestID: HJRPCId? { get }          // default: nil (UUID-based id is generated)

    func requestResult() async -> HJRPCResponse<Model>
    func request() async throws -> Model
    func notify() async throws
}
```

### Required Properties

- `method`: The JSON-RPC method name

### Optional Properties (with defaults)

- `parameters`: Typed parameters, `.named([String: Encodable & Sendable])` (encoded as a JSON object) or `.positioned([Encodable & Sendable])` (encoded as a JSON array)
- `requestID`: A custom `HJRPCId` (`.string`, `.number` or `.null`). When `nil`, a UUID-based string identifier is generated
- `isNotification`: Notifications carry no `id` and the server does not respond to them
- `needsAuth`, `retries`, `headers`: Same semantics as Harbor REST requests

## Response Types

### HJRPCResponse

```swift
enum HJRPCResponse<Model: Sendable> {
    case success(Model)
    case error(HJRPCRequestError)
}
```

### HJRPCRequestError

Server errors arrive as `HJRPCRequestError.jrpcError`, wrapping an `HJRPCError`:

```swift
struct HJRPCError {
    let code: Int
    let message: String
    let data: HJSONValue?       // optional extra info returned by the server

    var standardCode: HJRPCStandardCode?  // matching standard code, if any
    var isStandard: Bool                  // code is defined by the JSON-RPC spec
    var isServerError: Bool               // code is in -32099...-32000
}
```

Other relevant cases include `.urlNeeded` (endpoint not configured), `.invalidResponse` (malformed JSON-RPC response), `.idMismatch` (response id does not match the request id) and the network-level cases mirrored from `HRequestError`. `HJRPCRequestError` conforms to `LocalizedError`.

### Standard JSON-RPC Error Codes

| Code | `HJRPCStandardCode` | Meaning |
|------|---------|---------|
| -32700 | `.parseError` | Invalid JSON |
| -32600 | `.invalidRequest` | JSON-RPC structure invalid |
| -32601 | `.methodNotFound` | Method doesn't exist |
| -32602 | `.invalidParams` | Invalid method parameters |
| -32603 | `.internalError` | Server internal error |

## Ethereum JSON-RPC Examples

### Get Block Number

```swift
struct GetBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
}

// Usage
let response = await GetBlockNumberRequest().requestResult()
switch response {
case .success(let blockNumber):
    // blockNumber is a hex string like "0x1234567"
    print("Current block: \(blockNumber)")
case .error(let error):
    print("Error: \(error.localizedDescription)")
}
```

### Get Balance

```swift
struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_getBalance"
    let parameters: HJRPCParams?

    init(address: String, block: String = "latest") {
        self.parameters = .positioned([address, block])
    }
}

// Usage
let response = await GetBalanceRequest(
    address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
).requestResult()

switch response {
case .success(let balance):
    // balance is a hex string representing wei
    print("Balance: \(balance)")
case .error(let error):
    print("Error: \(error.localizedDescription)")
}
```

### Get Transaction by Hash

```swift
struct GetTransactionRequest: HJRPCRequestProtocol {
    typealias Model = Transaction
    let method: String = "eth_getTransactionByHash"
    let parameters: HJRPCParams?

    init(hash: String) {
        self.parameters = .positioned([hash])
    }
}

struct Transaction: Codable, Sendable {
    let hash: String
    let from: String
    let to: String
    let value: String
    let gas: String
    let gasPrice: String
    let nonce: String
    let blockNumber: String?
    let blockHash: String?
}

// Usage
let response = await GetTransactionRequest(
    hash: "0x1234567890abcdef..."
).requestResult()

switch response {
case .success(let transaction):
    print("From: \(transaction.from)")
    print("To: \(transaction.to)")
    print("Value: \(transaction.value)")
case .error(let error):
    print("Error: \(error.localizedDescription)")
}
```

### Call Contract Method

```swift
struct CallContractRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_call"
    let parameters: HJRPCParams?

    init(to: String, data: String, block: String = "latest") {
        self.parameters = .positioned([
            ["to": to, "data": data],
            block
        ])
    }
}

// Usage - Call a contract's read-only method
let response = await CallContractRequest(
    to: "0x1234567890abcdef...",  // Contract address
    data: "0x70a08231..."           // Encoded function call
).requestResult()
```

### Send Transaction

```swift
struct SendTransactionRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_sendRawTransaction"
    let parameters: HJRPCParams?

    init(signedTransaction: String) {
        self.parameters = .positioned([signedTransaction])
    }
}

// Usage
let response = await SendTransactionRequest(
    signedTransaction: "0xf86c..."  // Signed transaction hex
).requestResult()

switch response {
case .success(let txHash):
    print("Transaction hash: \(txHash)")
case .error(let error):
    print("Failed to send: \(error.localizedDescription)")
}
```

## Bitcoin JSON-RPC Examples

### Configure Bitcoin RPC

```swift
// Bitcoin Core RPC endpoint
await HarborJRPC.setURL(URL(string: "http://localhost:8332")!)

// You may need authentication headers
await Harbor.setDefaultHeaderParameters([
    "Authorization": "Basic \(base64Credentials)"
])
```

### Get Block Count

```swift
struct GetBlockCountRequest: HJRPCRequestProtocol {
    typealias Model = Int
    let method: String = "getblockcount"
}

let response = await GetBlockCountRequest().requestResult()
```

### Get Block Hash

```swift
struct GetBlockHashRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "getblockhash"
    let parameters: HJRPCParams?

    init(height: Int) {
        self.parameters = .positioned([height])
    }
}

let response = await GetBlockHashRequest(height: 750000).requestResult()
```

### Get Block

```swift
struct GetBlockRequest: HJRPCRequestProtocol {
    typealias Model = Block
    let method: String = "getblock"
    let parameters: HJRPCParams?

    init(hash: String, verbosity: Int = 1) {
        self.parameters = .positioned([hash, verbosity])
    }
}

struct Block: Codable, Sendable {
    let hash: String
    let height: Int
    let time: Int
    let tx: [String]
    let size: Int
    let weight: Int
}
```

## Notifications

Set `isNotification` to `true` and call `notify()`. Notifications carry no `id` and the server does not respond to them. Calling `notify()` on a request that is not a notification throws `HJRPCRequestError.invalidRequest`.

```swift
struct UnsubscribeRequest: HJRPCRequestProtocol {
    typealias Model = Bool
    let method: String = "eth_unsubscribe"
    let isNotification: Bool = true
    let parameters: HJRPCParams?

    init(subscriptionID: String) {
        self.parameters = .positioned([subscriptionID])
    }
}

try await UnsubscribeRequest(subscriptionID: "0x123").notify()
```

## Batch Requests

Use `HarborJRPC.batch(_:)` to send several JSON-RPC requests as a single batch call (JSON-RPC 2.0, section 6):

```swift
let responses = await HarborJRPC.batch([
    GetBlockNumberRequest(),
    GetBalanceRequest(address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb")
])

for response in responses {
    switch response {
    case .success(let id, let result):
        // result is the raw HJSONValue returned for the request with the given id
        print("Response for \(id?.description ?? "unknown"): \(result)")
    case .error(let id, let error):
        print("Error for \(id?.description ?? "unknown"): \(error.localizedDescription)")
    }
}
```

Notifications included in a batch do not produce a response element. Servers may reorder or omit responses, so each `HJRPCBatchResponse` is paired with the identifier echoed by the server. Set `requestID` on your requests if you need stable identifiers to match responses against.

## Custom RPC Endpoints

### Generic JSON-RPC Request

```swift
struct GenericJRPCRequest<T: Codable & Sendable>: HJRPCRequestProtocol {
    typealias Model = T
    let method: String
    let parameters: HJRPCParams?

    init(method: String, parameters: HJRPCParams? = nil) {
        self.method = method
        self.parameters = parameters
    }
}

// Usage for any JSON-RPC method
let response = await GenericJRPCRequest<String>(
    method: "custom_method",
    parameters: .named(["key": "value"])
).requestResult()
```

## Error Handling

### Comprehensive Error Handling

```swift
let response = await GetBlockNumberRequest().requestResult()

switch response {
case .success(let blockNumber):
    print("Block: \(blockNumber)")

case .error(let error):
    switch error {
    case .jrpcError(let jrpcError):
        switch jrpcError.standardCode {
        case .parseError:
            print("Parse error: Invalid JSON")
        case .invalidRequest:
            print("Invalid request structure")
        case .methodNotFound:
            print("Method not found")
        case .invalidParams:
            print("Invalid parameters")
        case .internalError:
            print("Internal server error")
        case nil:
            if jrpcError.isServerError {
                print("Server error \(jrpcError.code): \(jrpcError.message)")
            } else {
                print("Error \(jrpcError.code): \(jrpcError.message)")
            }
        }
    case .urlNeeded:
        print("JSON-RPC URL is not configured")
    case .noConnection:
        print("No internet connection")
    default:
        print("Error: \(error.localizedDescription)")
    }
}
```

### Retry with Error Recovery

```swift
func executeJRPCWithRetry<T: HJRPCRequestProtocol>(
    request: T,
    maxRetries: Int = 3
) async -> T.Model? {
    for attempt in 1...maxRetries {
        let response = await request.requestResult()

        switch response {
        case .success(let result):
            return result

        case .error(let error):
            print("Attempt \(attempt) failed: \(error.localizedDescription)")

            // Retry on internal or implementation-defined server errors
            if case .jrpcError(let jrpcError) = error,
               jrpcError.standardCode == .internalError || jrpcError.isServerError {
                if attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    continue
                }
            }

            // Don't retry client errors
            return nil
        }
    }
    return nil
}
```

## Debug Mode

### Debug JSON-RPC Requests

```swift
struct DebugBlockNumberRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"

    var debugType: HDebugRequestType = .requestAndResponse
}

// Enable logging
await Harbor.setLoggingEnabled(true)

// Execute - will log request and response
let response = await DebugBlockNumberRequest().requestResult()

// Output:
// curl -X POST "https://ethereum.publicnode.com" \
//   -H "Content-Type: application/json" \
//   -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":"..."}'
//
// Response: {"jsonrpc":"2.0","id":"...","result":"0x1234567"}
```

## Advanced Patterns

### Parallel Requests

```swift
func loadBlockchainData() async -> (String?, String?) {
    async let blockNumber = GetBlockNumberRequest().requestResult()
    async let gasPrice = GetGasPriceRequest().requestResult()

    let (block, gas) = await (blockNumber, gasPrice)

    let blockResult = if case .success(let b) = block { b } else { nil }
    let gasResult = if case .success(let g) = gas { g } else { nil }

    return (blockResult, gasResult)
}
```

For server-side batching in a single HTTP call, prefer `HarborJRPC.batch(_:)` (see above).

### Streaming JSON-RPC Data

```swift
actor BlockNumberMonitor {
    private var isRunning = false
    private var currentBlock: String?

    func startMonitoring(interval: TimeInterval = 12.0) async {
        guard !isRunning else { return }
        isRunning = true

        while isRunning {
            let response = await GetBlockNumberRequest().requestResult()

            if case .success(let blockNumber) = response {
                if blockNumber != currentBlock {
                    currentBlock = blockNumber
                    await notifyBlockChange(blockNumber)
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func stopMonitoring() {
        isRunning = false
    }

    private func notifyBlockChange(_ blockNumber: String) async {
        // Notify observers
        print("New block: \(blockNumber)")
    }
}

// Usage
let monitor = BlockNumberMonitor()
await monitor.startMonitoring(interval: 12.0)  // Every 12 seconds
```

## SwiftUI Integration

### JSON-RPC in SwiftUI

```swift
struct BlockNumberView: View {
    @State private var blockNumber: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading block...")
            } else if let blockNumber = blockNumber {
                Text("Current Block")
                    .font(.headline)
                Text(blockNumber)
                    .font(.system(.title, design: .monospaced))
            } else if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }

            Button("Refresh") {
                Task {
                    await loadBlockNumber()
                }
            }
        }
        .task {
            await loadBlockNumber()
        }
    }

    func loadBlockNumber() async {
        isLoading = true
        defer { isLoading = false }

        let response = await GetBlockNumberRequest().requestResult()

        await MainActor.run {
            switch response {
            case .success(let block):
                self.blockNumber = block
                self.errorMessage = nil
            case .error(let error):
                self.blockNumber = nil
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
```

### Polling Pattern

```swift
struct LiveBlockNumberView: View {
    @State private var blockNumber: String?
    @State private var isPolling = false

    var body: some View {
        VStack {
            Text("Block: \(blockNumber ?? "...")")

            Button(isPolling ? "Stop" : "Start") {
                isPolling.toggle()
            }
        }
        .task(id: isPolling) {
            guard isPolling else { return }

            while isPolling {
                await loadBlockNumber()
                try? await Task.sleep(nanoseconds: 12_000_000_000) // 12 seconds
            }
        }
    }

    func loadBlockNumber() async {
        let response = await GetBlockNumberRequest().requestResult()

        await MainActor.run {
            if case .success(let block) = response {
                self.blockNumber = block
            }
        }
    }
}
```

## Testing JSON-RPC Requests

JSON-RPC requests run through internal wrapper types, so mocks are registered against `HJRPCRequestWrapper<Model>.self` (or `HJRPCBatchWrapper.self` for batches), which requires `@testable import HarborJRPC`. The mocked JSON must be the full JSON-RPC response envelope, including the `jsonrpc` version and the same `id` the request sends — give the request a fixed `requestID` so the ids match.

### Mock JSON-RPC Response

```swift
// A request with a fixed requestID, so the mock envelope id can match
struct TestBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
    let requestID: HJRPCId? = .number(1)
}

func testGetBlockNumber() async throws {
    // Given
    await HarborJRPC.configure(url: URL(string: "https://api.example.com/rpc")!, jrpcVersion: "2.0")

    let mockJSON = """
    {
        "jsonrpc": "2.0",
        "id": 1,
        "result": "0x1234567"
    }
    """

    let mock = await HMock(
        request: HJRPCRequestWrapper<String>.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)

    // When
    let response = await TestBlockNumberRequest().requestResult()

    // Then
    switch response {
    case .success(let blockNumber):
        XCTAssertEqual(blockNumber, "0x1234567")
    case .error(let error):
        XCTFail("Expected success but got error: \(error.localizedDescription)")
    }
}
```

### Mock JSON-RPC Error

```swift
func testJRPCError() async throws {
    // Given
    let mockJSON = """
    {
        "jsonrpc": "2.0",
        "id": 1,
        "error": {
            "code": -32601,
            "message": "Method not found"
        }
    }
    """

    let mock = await HMock(
        request: HJRPCRequestWrapper<String>.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)

    // When
    let response = await TestBlockNumberRequest().requestResult()

    // Then
    switch response {
    case .success:
        XCTFail("Expected error but got success")
    case .error(let error):
        guard case .jrpcError(let jrpcError) = error else {
            return XCTFail("Expected jrpcError but got: \(error.localizedDescription)")
        }
        XCTAssertEqual(jrpcError.code, -32601)
        XCTAssertEqual(jrpcError.message, "Method not found")
        XCTAssertEqual(jrpcError.standardCode, .methodNotFound)
    }
}
```

## Best Practices

### 1. Configure Endpoint Once

```swift
// In AppDelegate or app initialization
await HarborJRPC.configure(url: URL(string: "https://ethereum.publicnode.com")!, jrpcVersion: "2.0")
```

### 2. Use Type-Safe Models

```swift
// Define proper response models
struct BlockData: Codable, Sendable {
    let number: String
    let hash: String
    let timestamp: String
    let transactions: [String]
}

struct GetBlockRequest: HJRPCRequestProtocol {
    typealias Model = BlockData
    let method = "eth_getBlockByNumber"
    let parameters: HJRPCParams?
}
```

### 3. Use Typed Parameters

```swift
// Good: typed parameters, no @unchecked Sendable needed
var parameters: HJRPCParams? {
    .named(["address": address, "block": block])
}

// Good: positional parameters
var parameters: HJRPCParams? {
    .positioned([address, block])
}
```

### 4. Handle Both Success and Error Cases

```swift
switch response {
case .success(let result):
    // Handle success
case .error(let error):
    // Always handle errors (HJRPCRequestError conforms to LocalizedError)
    print(error.localizedDescription)
}
```

### 5. Use Debug Mode During Development

```swift
struct DebugRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    // ... protocol conformance
    var debugType: HDebugRequestType = .requestAndResponse
}
```

### 6. Implement Retry Logic for Transient Errors

```swift
// Retry on server errors (.internalError, isServerError)
// Don't retry on client errors (.invalidRequest, .methodNotFound, .invalidParams)
```

## Related Files

**JSON-RPC Implementation:**
- `Sources/HarborJRPC/Request/HJRPCRequestProtocol.swift` - Protocol definition and internal request wrapper
- `Sources/HarborJRPC/Request/HJRPCRequestManager.swift` - Request execution, notifications and batches
- `Sources/HarborJRPC/HarborJRPC.swift` - Configuration entry point
- `Sources/HarborJRPC/Config/HJRPCConfig.swift` - Configuration storage

**Examples:**
- `Example/HarborExample/Requests/JRPCRequest.swift` - JSON-RPC example
- `Tests/HarborJRPCTests/` - JSON-RPC tests

**More Examples:**
- [basic.md](basic.md) - Basic REST patterns
- [advanced.md](advanced.md) - Advanced patterns
