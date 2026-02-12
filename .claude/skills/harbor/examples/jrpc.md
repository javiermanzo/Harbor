# Harbor JSON-RPC Examples

Complete guide to using Harbor's JSON-RPC 2.0 support.

## Overview

HarborJRPC is a separate module that provides JSON-RPC 2.0 support built on top of Harbor's REST functionality.

**Location**: `Sources/HarborJRPC/`

## Basic Setup

### Configure JSON-RPC Endpoint

```swift
// Set the JSON-RPC endpoint once at app startup
await HarborJRPC.setURL("https://ethereum.publicnode.com")

// All JSON-RPC requests will use this endpoint
```

### Simple JSON-RPC Request

```swift
struct GetBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
    let params: [String: Any]? = nil
}

// Execute
let response = await GetBlockNumberRequest().request()
switch response {
case .success(let blockNumber):
    print("Block number: \(blockNumber)")
case .error(let code, let message):
    print("Error \(code): \(message)")
}
```

## JSON-RPC Request Protocol

### Protocol Definition

```swift
protocol HJRPCRequestProtocol {
    associatedtype Model: Decodable, Sendable
    var method: String { get }
    var params: [String: Any]? { get }
}
```

### Required Properties

- `method`: The JSON-RPC method name
- `params`: Optional parameters dictionary (can be `nil`)

## Response Types

### HJRPCResponse

```swift
enum HJRPCResponse<Model: Decodable> {
    case success(result: Model)
    case error(code: Int, message: String)
}
```

### Standard JSON-RPC Error Codes

| Code | Message | Meaning |
|------|---------|---------|
| -32700 | Parse error | Invalid JSON |
| -32600 | Invalid Request | JSON-RPC structure invalid |
| -32601 | Method not found | Method doesn't exist |
| -32602 | Invalid params | Invalid method parameters |
| -32603 | Internal error | Server internal error |

## Ethereum JSON-RPC Examples

### Get Block Number

```swift
struct GetBlockNumberRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_blockNumber"
    let params: [String: Any]? = nil
}

// Usage
let response = await GetBlockNumberRequest().request()
switch response {
case .success(let blockNumber):
    // blockNumber is a hex string like "0x1234567"
    print("Current block: \(blockNumber)")
case .error(let code, let message):
    print("Error \(code): \(message)")
}
```

### Get Balance

```swift
struct GetBalanceRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_getBalance"
    let params: [String: Any]?
    
    init(address: String, block: String = "latest") {
        self.params = [
            "address": address,
            "block": block
        ]
    }
}

// Usage
let response = await GetBalanceRequest(
    address: "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb"
).request()

switch response {
case .success(let balance):
    // balance is a hex string representing wei
    print("Balance: \(balance)")
case .error(let code, let message):
    print("Error \(code): \(message)")
}
```

### Get Transaction by Hash

```swift
struct GetTransactionRequest: HJRPCRequestProtocol {
    typealias Model = Transaction
    let method: String = "eth_getTransactionByHash"
    let params: [String: Any]?
    
    init(hash: String) {
        self.params = ["hash": hash]
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
).request()

switch response {
case .success(let transaction):
    print("From: \(transaction.from)")
    print("To: \(transaction.to)")
    print("Value: \(transaction.value)")
case .error(let code, let message):
    print("Error \(code): \(message)")
}
```

### Call Contract Method

```swift
struct CallContractRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_call"
    let params: [String: Any]?
    
    init(to: String, data: String, block: String = "latest") {
        self.params = [
            "transaction": [
                "to": to,
                "data": data
            ],
            "block": block
        ]
    }
}

// Usage - Call a contract's read-only method
let response = await CallContractRequest(
    to: "0x1234567890abcdef...",  // Contract address
    data: "0x70a08231..."           // Encoded function call
).request()
```

### Send Transaction

```swift
struct SendTransactionRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "eth_sendRawTransaction"
    let params: [String: Any]?
    
    init(signedTransaction: String) {
        self.params = ["signed_tx": signedTransaction]
    }
}

// Usage
let response = await SendTransactionRequest(
    signedTransaction: "0xf86c..."  // Signed transaction hex
).request()

switch response {
case .success(let txHash):
    print("Transaction hash: \(txHash)")
case .error(let code, let message):
    print("Failed to send: \(message)")
}
```

## Bitcoin JSON-RPC Examples

### Configure Bitcoin RPC

```swift
// Bitcoin Core RPC endpoint
await HarborJRPC.setURL("http://localhost:8332")

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
    let params: [String: Any]? = nil
}

let response = await GetBlockCountRequest().request()
```

### Get Block Hash

```swift
struct GetBlockHashRequest: HJRPCRequestProtocol {
    typealias Model = String
    let method: String = "getblockhash"
    let params: [String: Any]?
    
    init(height: Int) {
        self.params = ["height": height]
    }
}

let response = await GetBlockHashRequest(height: 750000).request()
```

### Get Block

```swift
struct GetBlockRequest: HJRPCRequestProtocol {
    typealias Model = Block
    let method: String = "getblock"
    let params: [String: Any]?
    
    init(hash: String, verbosity: Int = 1) {
        self.params = [
            "blockhash": hash,
            "verbosity": verbosity
        ]
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

## Custom RPC Endpoints

### Generic JSON-RPC Request

```swift
struct GenericJRPCRequest<T: Codable & Sendable>: HJRPCRequestProtocol {
    typealias Model = T
    let method: String
    let params: [String: Any]?
    
    init(method: String, params: [String: Any]? = nil) {
        self.method = method
        self.params = params
    }
}

// Usage for any JSON-RPC method
let response = await GenericJRPCRequest<String>(
    method: "custom_method",
    params: ["key": "value"]
).request()
```

## Error Handling

### Comprehensive Error Handling

```swift
let response = await GetBlockNumberRequest().request()

switch response {
case .success(let blockNumber):
    print("Block: \(blockNumber)")
    
case .error(let code, let message):
    switch code {
    case -32700:
        print("Parse error: Invalid JSON")
    case -32600:
        print("Invalid request structure")
    case -32601:
        print("Method '\(methodName)' not found")
    case -32602:
        print("Invalid parameters")
    case -32603:
        print("Internal server error")
    default:
        print("Error \(code): \(message)")
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
        let response = await request.request()
        
        switch response {
        case .success(let result):
            return result
            
        case .error(let code, let message):
            print("Attempt \(attempt) failed: \(code) - \(message)")
            
            // Retry on temporary errors
            if code == -32603 || code == -32000 {
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
    let params: [String: Any]? = nil
    
    var debugType: HDebugRequestType = .requestAndResponse
}

// Enable logging
await Harbor.setLoggingEnabled(true)

// Execute - will log request and response
let response = await DebugBlockNumberRequest().request()

// Output:
// curl -X POST "https://ethereum.publicnode.com" \
//   -H "Content-Type: application/json" \
//   -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
//
// Response: {"jsonrpc":"2.0","id":1,"result":"0x1234567"}
```

## Advanced Patterns

### Batch Requests

```swift
func loadBlockchainData() async -> (String?, String?, String?) {
    async let blockNumber = GetBlockNumberRequest().request()
    async let gasPrice = GetGasPriceRequest().response()
    async let chainId = GetChainIdRequest().request()
    
    let (block, gas, chain) = await (blockNumber, gasPrice, chainId)
    
    let blockResult = if case .success(let b) = block { b } else { nil }
    let gasResult = if case .success(let g) = gas { g } else { nil }
    let chainResult = if case .success(let c) = chain { c } else { nil }
    
    return (blockResult, gasResult, chainResult)
}
```

### Request with Cache

```swift
// Note: JSON-RPC requests are POST, so caching requires custom implementation
// You can wrap in a GET request for caching

struct CachedBlockNumberRequest: HGetRequestProtocol {
    typealias Model = String
    let url: String = "https://ethereum.publicnode.com"
    let cacheConfiguration: HCache.Configuration? = .enabled(expirationTime: .fiveMinutes)
    
    // Custom implementation to call JSON-RPC
    func request() async -> HResponseWithResult<String> {
        // First check cache
        if let cached = await self.cache() {
            return .success(result: cached)
        }
        
        // Otherwise call JSON-RPC
        let jrpcResponse = await GetBlockNumberRequest().request()
        
        switch jrpcResponse {
        case .success(let blockNumber):
            return .success(result: blockNumber)
        case .error(let code, let message):
            return .error(.serverError(statusCode: code, data: message.data(using: .utf8)))
        }
    }
}
```

### Streaming JSON-RPC Data

```swift
actor BlockNumberMonitor {
    private var isRunning = false
    private var currentBlock: String?
    
    func startMonitoring(interval: TimeInterval = 12.0) async {
        guard !isRunning else { return }
        isRunning = true
        
        while isRunning {
            let response = await GetBlockNumberRequest().request()
            
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
        
        let response = await GetBlockNumberRequest().request()
        
        await MainActor.run {
            switch response {
            case .success(let block):
                self.blockNumber = block
                self.errorMessage = nil
            case .error(let code, let message):
                self.blockNumber = nil
                self.errorMessage = "Error \(code): \(message)"
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
        let response = await GetBlockNumberRequest().request()
        
        await MainActor.run {
            if case .success(let block) = response {
                self.blockNumber = block
            }
        }
    }
}
```

## Testing JSON-RPC Requests

### Mock JSON-RPC Response

```swift
func testGetBlockNumber() async throws {
    // Given
    let mockJSON = """
    {
        "jsonrpc": "2.0",
        "id": 1,
        "result": "0x1234567"
    }
    """
    
    let mock = await HMock(
        request: GetBlockNumberRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetBlockNumberRequest().request()
    
    // Then
    switch response {
    case .success(let blockNumber):
        XCTAssertEqual(blockNumber, "0x1234567")
    case .error(let code, let message):
        XCTFail("Expected success but got error \(code): \(message)")
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
        request: GetBlockNumberRequest.self,
        statusCode: 200,
        jsonResponse: mockJSON
    )
    await Harbor.register(mock: mock)
    
    // When
    let response = await GetBlockNumberRequest().request()
    
    // Then
    switch response {
    case .success:
        XCTFail("Expected error but got success")
    case .error(let code, let message):
        XCTAssertEqual(code, -32601)
        XCTAssertEqual(message, "Method not found")
    }
}
```

## Best Practices

### 1. Configure Endpoint Once

```swift
// In AppDelegate or app initialization
await HarborJRPC.setURL("https://ethereum.publicnode.com")
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
    let params: [String: Any]?
}
```

### 3. Handle Both Success and Error Cases

```swift
switch response {
case .success(let result):
    // Handle success
case .error(let code, let message):
    // Always handle errors
}
```

### 4. Use Debug Mode During Development

```swift
struct DebugRequest: HJRPCRequestProtocol, HDebugRequestProtocol {
    // ... protocol conformance
    var debugType: HDebugRequestType = .requestAndResponse
}
```

### 5. Implement Retry Logic for Transient Errors

```swift
// Retry on server errors (-32603)
// Don't retry on client errors (-32600, -32601, -32602)
```

## Related Files

**JSON-RPC Implementation:**
- `Sources/HarborJRPC/Request/HJRPCRequestProtocol.swift` - Protocol definition
- `Sources/HarborJRPC/Request/HJRPCRequestWrapper.swift` - Internal adapter
- `Sources/HarborJRPC/Config/HarborJRPC.swift` - Configuration

**Examples:**
- `Example/HarborExample/Requests/JRPCRequest.swift` - JSON-RPC example
- `Tests/HarborJRPCTests/` - JSON-RPC tests

**More Examples:**
- [basic.md](basic.md) - Basic REST patterns
- [advanced.md](advanced.md) - Advanced patterns
