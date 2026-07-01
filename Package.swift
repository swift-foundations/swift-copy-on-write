// swift-tools-version: 6.2

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "swift-copy-on-write",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(
            name: "Copy on Write",
            targets: ["Copy on Write"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"604.0.0"),
    ],
    targets: [
        // Public API - the @CoW macro declaration
        .target(
            name: "Copy on Write",
            dependencies: ["Copy on Write Macros"]
        ),

        // Macro implementation - compiler plugin
        .macro(
            name: "Copy on Write Macros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),

        // Tests
        .testTarget(
            name: "Copy on Write Tests",
            dependencies: [
                "Copy on Write",
                "Copy on Write Macros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
