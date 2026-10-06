// swift-tools-version: 6.2
import PackageDescription

/// Treat all warnings as errors. Applies to this package's targets only.
let strictSettings: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "WFRouter",
    platforms: [
        .iOS("18.4"),
    ],
    products: [
        .library(name: "WFRouter", targets: ["WFRouter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/WildFunction/WildFunctionKit.git", from: "0.2.0"),
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
