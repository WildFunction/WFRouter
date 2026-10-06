// swift-tools-version: 6.2
import PackageDescription

/// Warnings are errors only when WFROUTER_STRICT is set (CI and local development).
/// It must stay off for consumers: Xcode suppresses warnings in remote packages,
/// and combining that with warnings-as-errors fails the build.
let strictSettings: [SwiftSetting] = Context.environment["WFROUTER_STRICT"] == nil
    ? []
    : [.treatAllWarnings(as: .error)]

let package = Package(
    name: "WFRouter",
    platforms: [
        .iOS("18.4"),
    ],
    products: [
        .library(name: "WFRouter", targets: ["WFRouter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/WildFunction/WildFunctionKit.git", from: "0.2.1"),
    ],
    targets: [
        .target(
            name: "WFRouter",
            dependencies: [.product(name: "WildFunctionKit", package: "WildFunctionKit")],
            swiftSettings: strictSettings
        ),
        .testTarget(name: "WFRouterTests", dependencies: ["WFRouter"], swiftSettings: strictSettings),
    ],
    swiftLanguageModes: [.v6]
)
