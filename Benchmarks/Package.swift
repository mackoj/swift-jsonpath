// swift-tools-version: 6.1
import PackageDescription

// swift-jsonpath's benchmarks, on ordo-one/package-benchmark (https://www.swift.org/blog/benchmarks/). A separate
// package so the benchmark dependency and Foundation stay out of the library's dependency budget. Run from the
// repository root: `swift package --package-path Benchmarks benchmark`.
let package = Package(
    name: "Benchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(name: "swift-jsonpath", path: ".."),
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.38.0"),
    ],
    targets: [
        .executableTarget(
            name: "JSONPathBenchmarks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "JSONPath", package: "swift-jsonpath"),
            ],
            path: "Benchmarks/JSONPathBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        ),
        // Reads two `benchmark --format markdown` outputs and prints each benchmark's p50 before and after.
        .executableTarget(name: "p50", path: "Tools/P50"),
        // Reads an exported Time Profiler table and prints the hottest functions (scripts/profile.sh).
        .executableTarget(name: "hotspots", path: "Tools/Hotspots"),
    ]
)
