import LLMCheck

/// The swift-jsonpath repository, rooted where `.llm-check.yaml` is. Its file list and every parsed file are shared
/// by all suites, which Swift Testing runs in parallel.
func jsonPath() throws -> Codebase { try Codebase() }

extension RuleCategory {
    static let platforms = RuleCategory(
        "platforms",
        description: "The dependency budget. Read before you add an `import` to `Sources`."
    )
    static let purity = RuleCategory(
        "purity",
        description: "The library is pure. Read before you print, read input or reach for randomness."
    )
    static let models = RuleCategory(
        "models",
        description: "Public types and concurrency. Read before you add or change a public type."
    )
    static let testing = RuleCategory(
        "testing",
        description: "Swift Testing, no silenced tests and no stubs. Read before you add, skip or mark a test."
    )
}
