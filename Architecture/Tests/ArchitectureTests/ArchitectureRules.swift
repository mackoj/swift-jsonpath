import LLMCheck
import Testing

/// The rules, run on the repository. A failure prints the rule, why it exists and how to fix it.
@Suite("Architecture rules")
struct ArchitectureRules {
    static func sources() throws -> Scope { try jsonPath().productionCode.in("/Sources") }
    static func tests() throws -> Scope { try jsonPath().testCode.in("/Tests") }

    @Test func sourcesImportNothing() throws {
        let sources = try Self.sources()
        #expect(sources.relativePaths.count > 10, "is .llm-check.yaml at the repository root?")
        expectNone(Detect.imports(in: sources), rule: .sourcesImportNothing)
    }

    @Test func libraryPerformsNoIO() throws {
        expectNone(Detect.impureCode(in: try Self.sources()), rule: .libraryPerformsNoIO)
    }

    @Test func publicTypesAreValues() throws {
        expectNone(Detect.publicReferenceTypes(in: try Self.sources()), rule: .publicTypesAreValues)
    }

    @Test func publicTypesAreHashableAndSendable() throws {
        let sources = try Self.sources()
        #expect(sources.structs.withModifier("public").count > 5)
        expectNone(Detect.publicTypesMissingConformances(in: sources), rule: .publicTypesAreHashableAndSendable)
    }

    @Test func uncheckedSendableExplainsItself() throws {
        expectNone(Detect.uncommentedUncheckedSendable(in: try Self.sources()), rule: .uncheckedSendableExplainsItself)
    }

    @Test func noTodoStubs() throws {
        expectNone(Detect.todoStubs(in: try jsonPath().allCode), rule: .noTodoStubs)
    }

    @Test func testsUseSwiftTesting() throws {
        let tests = try Self.tests()
        #expect(tests.containing("import Testing").relativePaths.count > 5)
        expectNone(Detect.xcTestImports(in: tests), rule: .testsUseSwiftTesting)
    }

    @Test func knownIssuesExplainThemselves() throws {
        expectNone(Detect.unexplainedKnownIssues(in: try Self.tests()), rule: .knownIssuesExplainThemselves)
    }

    @Test func testsAreNotDisabled() throws {
        expectNone(Detect.disabledTests(in: try Self.tests()), rule: .testsAreNotDisabled)
    }
}

/// Keeps `docs/architecture-rules.md` in step with the rules. Regenerate with
/// `LLM_CHECK_RECORD=1 swift test --package-path Architecture`.
@Test func rulesDocumentIsUpToDate() throws {
    let catalog = RuleCatalog(allRules)
    #expect(catalog.duplicateIDs.isEmpty)
    try expectFile(
        "docs/architecture-rules.md", in: jsonPath(),
        matches: catalog.markdown(
            title: "Architecture rules",
            introduction: """
                The mechanical part of `CODING_STANDARDS.md` and `CONSTRAINTS.md`, enforced by the `Architecture/` \
                package with [swift-llm-check](https://github.com/mackoj/swift-llm-check): \
                `swift test --package-path Architecture` (macOS). Generated from its rules; do not edit by hand.
                """))
}
