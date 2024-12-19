// swift-tools-version: 5.10
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
    ],

    dependencies: [
        .package(url: "https://github.com/javiermanzo/LogBird", exact: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Harbor",
            dependencies: [
                .product(name: "LogBird", package: "LogBird"),
            ]),
        .testTarget(
            name: "HarborTests",
            dependencies: ["Harbor"]),

        .target(
            name: "HarborJRPC",
            dependencies: ["Harbor"]),
        .testTarget(
            name: "HarborJRPCTests",
            dependencies: ["HarborJRPC"]),
    ],
    swiftLanguageVersions: [.version("6"), .v5]
)
