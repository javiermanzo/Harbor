// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Harbor",
            targets: ["Harbor"]),
        .library(
            name: "HarborJRPC",
            targets: ["HarborJRPC"]),
        .library(
            name: "HarborWebSocket",
            targets: ["HarborWebSocket"]),
    ],

    dependencies: [
        .package(url: "https://github.com/javiermanzo/LogBird", from: "2.1.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        // Shared infrastructure (auth, security, logging, session pool, retry loop). Not a product:
        // its internals are `package`, and what was already public is re-exported by
        // `Harbor` and `HarborWebSocket`.
        .target(
            name: "HarborCore",
            dependencies: [
                .product(name: "LogBird", package: "LogBird"),
            ]),
        .target(
            name: "Harbor",
            dependencies: ["HarborCore"]),
        .testTarget(
            name: "HarborTests",
            dependencies: ["Harbor", "HarborCore"],
            exclude: ["certificate.p12", "certificate-ec256.der", "certificate-rsa4096.der"]),

        .target(
            name: "HarborJRPC",
            dependencies: ["Harbor"]),
        .testTarget(
            name: "HarborJRPCTests",
            dependencies: ["HarborJRPC"]),

        .target(
            name: "HarborWebSocket",
            dependencies: ["HarborCore"]),
        .testTarget(
            name: "HarborWebSocketTests",
            dependencies: ["HarborWebSocket", "HarborCore"]),
    ],
    swiftLanguageModes: [.v6]
)
