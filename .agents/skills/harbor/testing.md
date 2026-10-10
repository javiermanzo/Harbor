# Testing with Harbor

## How mocks work

Mocks are resolved inside Harbor's request manager, not at the `URLProtocol` level. On every attempt, when mocks are enabled and a mock is registered for `type(of: request)`, Harbor builds a synthetic `HTTPURLResponse` from the mock and runs it through the normal response pipeline (decoding, cache store, retry, 401 handling). No network call, connectivity check or URL session is involved.

Consequences:

- Mocked requests skip the connectivity check and the initial auth-header lookup, so Harbor never *generates* `.noConnection` or `.authProviderNeeded` for them. A mock's own `error` (for example `.noConnection`) is returned as-is.
- The status code still drives behavior. A mocked 503 is retried by the request's `retryPolicy`, a 2xx is decoded with `parseData(data:model:)` (and cached for GET requests), and a 401 calls the auth provider's `authFailed()`.
- A mock's `error` ends the attempt with that error, after `delay`, and goes through the retry policy like the real failure it stands for: `.timeout` is retried for idempotent requests, `.noConnection` / `.cannotFindHost` / `.cannotConnectToHost` for any method, `.api(statusCode:)` per `retryableStatusCodes`. Other errors are not retried.
- Mocks are keyed by request type identity: one mock (or sequence) per type.
- `HJRPCRequestProtocol` requests can't be mocked with `HMock`, because they are sent through internal wrapper types. Use a `URLProtocol` stub on a custom session instead (see below).

Mocks are on by default in DEBUG builds and off in release builds. `Harbor.setMocksEnabled(true/false)` turns them on or off (`setMocksEnabled(true)` also enables them in release, e.g. for a UI-test or demo configuration); read the current value with `Harbor.mocksEnabled`.

## API

```swift
struct Todo: Codable, Sendable, Equatable {
    let id: Int
    let title: String
}

struct GetTodoRequest: HGetRequestProtocol {
    typealias Model = Todo
    let url = "https://api.example.com/todos/1"
}

struct DeleteTodoRequest: HDeleteRequestProtocol {
    let url = "https://api.example.com/todos/1"
}

func mockAPI() async {
    await Harbor.setMocksEnabled(true)

    // Success with a JSON body, response headers and a simulated latency
    let mock = HMock(request: GetTodoRequest.self,
                     statusCode: 200,
                     jsonResponse: #"{"id":1,"title":"Write docs"}"#,
                     delay: 0.2,
                     headers: ["Cache-Control": "max-age=60", "ETag": "\"v1\""])
    await Harbor.register(mock: mock)

    // HTTP error: becomes HRequestError.api(statusCode: 404, data: ...)
    await Harbor.register(mock: HMock(request: DeleteTodoRequest.self, statusCode: 404))

    // Transport-level error injected directly
    await Harbor.register(mock: HMock(request: GetTodoRequest.self, statusCode: 0, error: .timeout))

    // Scripted sequence: one response per attempt, the last one repeats
    await Harbor.register(mockSequence: HMockSequence(request: GetTodoRequest.self, responses: [
        .init(statusCode: 503, headers: ["Retry-After": "0"]),
        .init(statusCode: 200, jsonResponse: #"{"id":1,"title":"Recovered"}"#)
    ]))

    let calls = await Harbor.mockCallCount(for: GetTodoRequest.self)
    let registered = await Harbor.isMockRegistered(for: GetTodoRequest.self)
    print(calls, registered)

    await Harbor.removeMock(for: GetTodoRequest.self) // removes the mock or sequence registered for GetTodoRequest
    await Harbor.removeAllMocks()                     // also resets call counts
}
```

Registering a mock replaces any mock or sequence for the same type, and vice versa. `HMockSequence(request:responses:)` takes `HMockSequence.Response` values (`.init(statusCode:jsonResponse:error:headers:delay:)`). `Harbor.mockCallCount(for:)` counts every mocked attempt for the type, retries included, since the last `removeAllMocks()`.

## XCTest patterns

```swift
final class TodoTests: XCTestCase {
    override func setUp() async throws {
        await Harbor.setMocksEnabled(true)
        await Harbor.removeAllMocks()
        await Harbor.clearAllCache()
        await Harbor.setAuthProvider(nil)
    }

    override func tearDown() async throws {
        await Harbor.removeAllMocks()
    }

    func testDecodesTodo() async {
        await Harbor.register(mock: HMock(request: GetTodoRequest.self,
                                          statusCode: 200,
                                          jsonResponse: #"{"id":1,"title":"Write docs"}"#))

        let response = await GetTodoRequest().request()

        guard case .success(let todo) = response else {
            return XCTFail("Expected success, got \(response)")
        }
        XCTAssertEqual(todo, Todo(id: 1, title: "Write docs"))
    }

    func testNotFound() async {
        await Harbor.register(mock: HMock(request: DeleteTodoRequest.self, statusCode: 404))

        guard case .error(let error) = await DeleteTodoRequest().request() else {
            return XCTFail("Expected an error")
        }
        guard case .api(let statusCode, _) = error else {
            return XCTFail("Expected .api, got \(error)")
        }
        XCTAssertEqual(statusCode, 404)
    }

    func testRetriesTransientFailure() async {
        struct RetryingTodoRequest: HGetRequestProtocol {
            typealias Model = Todo
            let url = "https://api.example.com/todos/1"
            let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 2, baseDelay: 0, jitter: 0...0)
        }
        await Harbor.register(mockSequence: HMockSequence(request: RetryingTodoRequest.self, responses: [
            .init(statusCode: 503),
            .init(statusCode: 200, jsonResponse: #"{"id":1,"title":"ok"}"#)
        ]))

        let response = await RetryingTodoRequest().request()

        guard case .success = response else { return XCTFail("\(response)") }
        let calls = await Harbor.mockCallCount(for: RetryingTodoRequest.self)
        XCTAssertEqual(calls, 2)
    }

    func testErrorsAreEquatable() async {
        await Harbor.register(mock: HMock(request: GetTodoRequest.self, statusCode: 0, error: .noConnection))

        guard case .error(let error) = await GetTodoRequest().request() else { return XCTFail() }
        XCTAssertEqual(error, .noConnection)
    }
}
```

### Auth refresh

```swift
actor RefreshCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

final class RotatingAuthProvider: HAuthProviderProtocol {
    let counter = RefreshCounter()

    func getAuthorizationHeader() async -> HAuthorizationHeader? {
        HAuthorizationHeader(key: "Authorization", value: "Bearer \(await counter.count)")
    }

    func authFailed() async {
        await counter.increment()
    }
}

struct SecureTodoRequest: HGetRequestProtocol {
    typealias Model = Todo
    let url = "https://api.example.com/secure/todo"
    let needsAuth = true
}

func authRefreshScenario() async -> Int {
    let provider = RotatingAuthProvider()
    await Harbor.setAuthProvider(provider)
    await Harbor.setMocksEnabled(true)
    await Harbor.register(mockSequence: HMockSequence(request: SecureTodoRequest.self, responses: [
        .init(statusCode: 401),
        .init(statusCode: 200, jsonResponse: #"{"id":2,"title":"secret"}"#)
    ]))

    _ = await SecureTodoRequest().request()   // 401 → authFailed() → new header → 200
    return await provider.counter.count        // 1
}
```

## Stubbing the network (custom session)

To exercise the real transport (cache headers through `URLCache`, JSON-RPC requests, redirects), install a `URLProtocol` subclass on a custom session:

```swift
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseBody = Data(#"{"jsonrpc":"2.0","id":"1","result":"0x10"}"#.utf8)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func installStubSession() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    await Harbor.setMocksEnabled(false)
    await Harbor.setCustomURLSession(URLSession(configuration: configuration))
}
```

Remember to call `await Harbor.setCustomURLSession(nil)` in `tearDown`. A JSON-RPC response's `id` must match the request's: set `requestID` on the request (for example `.string("1")`) when stubbing, otherwise the request fails with `.idMismatch`. Harbor's own test suite uses an internal `setProtocolClasses` hook (`@testable import Harbor`), which isn't part of the public API.

## Tips

- Reset global state in `setUp` / `tearDown`: mocks, cache, auth provider, custom session, pins.
- Harbor's configuration is global. Run tests that change it serially, or give each test its own request types.
- Use `HRetryPolicy(maxRetries:baseDelay: 0, jitter: 0...0)` in tests to avoid real backoff delays. `Retry-After: 0` on mocked 429/503 responses works too.
- Real-network tests in this repo run only with `HARBOR_RUN_NETWORK_TESTS=1`.

## Related files

- `Sources/Harbor/Mock/HMock.swift`, `HMockSequence.swift`, `HMocker.swift`.
- `Sources/Harbor/Request/HRequestManager+Execution.swift` (`executeMockAttempt`) and `HRequestManager+Mock.swift` (`resolveMock`).
- `Tests/HarborTests/HarborMockTests.swift`, `HarborRequestRetryTests.swift`.
