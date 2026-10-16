import Foundation
import HarborWebSocket   // no `import Harbor`: the shared configuration comes with HarborWebSocket

struct EchoSocket: HWebSocketRequestProtocol {
    let url = "ws://127.0.0.1:1/unreachable"
    let needsAuth = true
    let timeoutInterval: TimeInterval? = 2
    let retryPolicy: HRetryPolicy? = HRetryPolicy(maxRetries: 1)
}

await Harbor.setDefaultTimeoutInterval(5)
await Harbor.setSSLPinningKeys(nil)
await HarborWebSocket.setDefaultPingInterval(30)

// Without a provider the handshake must refuse to start: proves the shared configuration is wired.
do {
    _ = try await EchoSocket().connect()
    print("unexpected success")
} catch {
    print("connect failed as expected:", error)
}
