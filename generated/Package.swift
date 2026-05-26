// swift-tools-version:6.0

import Foundation
import PackageDescription

let package = Package(
    name: "generated",
    products: [
        .library(name: "CWinRT", targets: ["CWinRT"]),
        .library(name: "WindowsFoundation", targets: ["WindowsFoundation"]),

    ],
    targets: [
        .target(
            name: "CWinRT"
        ),
        .target(
            name: "WindowsFoundation",
            dependencies: [
                "CWinRT"
            ],
        ),
    ],
    swiftLanguageModes: [.v5]
)
