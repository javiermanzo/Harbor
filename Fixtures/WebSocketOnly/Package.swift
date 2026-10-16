// swift-tools-version: 6.0
import PackageDescription

// A consumer that depends on the HarborWebSocket product only. `scripts/check_websocket_only_link.sh`
// builds it and verifies that none of Harbor's REST code ends up in the binary.
let package = Package(
    name: "WebSocketOnly",
    platforms: [.iOS(.v15), .macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "WebSocketOnly",
            dependencies: [.product(name: "HarborWebSocket", package: "Harbor")]),
    ],
    swiftLanguageModes: [.v6]
)
