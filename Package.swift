// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "generated")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "CWinRT", package: "generated"),
                .product(name: "WindowsFoundation", package: "generated"),
            ],
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["App"],
        ),
    ],
    swiftLanguageModes: [.v6]
)
