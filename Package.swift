// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-jsonpath",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        // JSONPath (RFC 9535 and Jayway dialects), an order-preserving JSON value / parser,
        // Codable bridging, JSON Pointer and mutations. Pure Swift: no Foundation.
        .library(name: "JSONPath", targets: ["JSONPath"]),
    ],
    targets: [
        .target(
            name: "JSONPath",
            linkerSettings: [
                // `rounded()` / `squareRoot()` come from libm, which Foundation would otherwise pull in.
                .linkedLibrary("m", .when(platforms: [.linux, .android]))
            ]
        ),
        .testTarget(
            name: "JSONPathTests",
            dependencies: ["JSONPath"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
