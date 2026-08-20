// swift-tools-version: 6.4

import CompilerPluginSupport
import PackageDescription

extension String {
    static let copyOnWrite: Self = "Copy on Write"
    static let copyOnWriteMacros: Self = "Copy on Write Macros"
    var tests: Self { self + " Tests" }
}

extension Target.Dependency {
    static var copyOnWrite: Self { .target(name: .copyOnWrite) }
    static var copyOnWriteMacros: Self { .target(name: .copyOnWriteMacros) }
}

let package = Package(
    name: "swift-copy-on-write",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(
            name: .copyOnWrite,
            targets: [.copyOnWrite]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0")
    ],
    targets: [
        .target(
            name: .copyOnWrite,
            dependencies: [.copyOnWriteMacros]
        ),
        .macro(
            name: .copyOnWriteMacros,
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .testTarget(
            name: .copyOnWrite.tests,
            dependencies: [
                .copyOnWrite,
                .copyOnWriteMacros,
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/Copy on Write Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
