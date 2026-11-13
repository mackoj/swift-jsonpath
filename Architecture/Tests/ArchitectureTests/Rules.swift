import LLMCheck

extension Rule {
    static let sourcesImportNothing = Rule(
        id: "sources-import-nothing",
        title: "`Sources` imports nothing: no Foundation, no FoundationEssentials, no package, no libc.",
        category: .platforms,
        rationale: """
            swift-jsonpath is pure Swift with no imports at all (CONSTRAINTS.md, "Dependency budget"; \
            CODING_STANDARDS.md, "Standard library only"). Every client, on every platform, gets the library without \
            Foundation's size or its differences between Darwin and Linux. One import is a dependency for all of them.
            """,
        howToFix: """
            Write it against the standard library, as the number formatting, regexes and Unicode handling already \
            are. Platform differences go behind `#if os(…)` without importing anything; `rounded()` and \
            `squareRoot()` already link libm in `Package.swift`. A new dependency is a decision for the maintainer, \
            recorded in `Package.swift` and CONSTRAINTS.md first.
            """,
        badExample: """
            import Foundation
            let text = String(format: "%.17g", number)
            """,
        goodExample: """
            // Sources/JSONPath/JSONValue.swift: number formatting written against the standard library.
            let text = number.description
            """
    )

    static let libraryPerformsNoIO = Rule(
        id: "library-performs-no-io",
        title: "The library prints nothing, reads no input or arguments and uses no randomness.",
        category: .purity,
        rationale: """
            swift-jsonpath is a pure library (CODING_STANDARDS.md, "Pure library"): callers pass data in and get \
            values back, so the same query on the same document gives the same result on every platform and in \
            every test. `print` writes to a host's standard output, `readLine` and `CommandLine` read the process's, \
            and `random`, `shuffled` and `randomElement` make results differ from one run to the next.
            """,
        howToFix: """
            Return the value, or report a problem as a thrown `JSONPath.ParseError`, `EvaluationError` or \
            `JSONValue.MutationError`. Take anything the caller knows as a parameter.
            """,
        badExample: """
            print("unknown function \\(name)")
            let pick = values.randomElement()
            """,
        goodExample: """
            throw JSONPath.ParseError(message: "unknown function \\(name)", position: start)
            """
    )

    static let publicTypesAreValues = Rule(
        id: "public-types-are-values",
        title: "A public type is a `struct` or an `enum`, never a `class` or an `actor`.",
        category: .models,
        rationale: """
            Public types are values (CODING_STANDARDS.md, "Sendable value types"): a `JSONValue` or a `JSONPath` \
            copied into another task cannot change under the caller, and tests compare whole values. A public \
            class shares mutable state with every holder; turning it into a struct later breaks clients.
            """,
        howToFix: """
            Make it a `struct` or an `enum`. Reference storage that a value type needs stays internal, like \
            `ObjectStorage` in `JSONValueCoding.swift`.
            """,
        badExample: "public final class JSONPointer {",
        goodExample: "public struct JSONPointer: Hashable, Sendable {"
    )

    static let publicTypesAreHashableAndSendable = Rule(
        id: "public-types-are-hashable-and-sendable",
        title: "A public struct or enum is declared `Sendable`, and `Hashable` unless it holds `any Sendable`.",
        category: .models,
        rationale: """
            Public types are `Sendable` and `Hashable` (CODING_STANDARDS.md, "Sendable value types"): `Sendable` \
            lets clients share a parsed path or a document across tasks under Swift 6, and `Hashable` lets tests \
            compare whole values and clients use them as keys. A missing conformance is a source break to add \
            later, since a client cannot add it. `JSONValueDecoder` and `JSONValueEncoder` are `Sendable` only: \
            their `userInfo` holds `any Sendable` values, which cannot be compared.
            """,
        howToFix: """
            Declare both on the type itself, like its neighbours: `public struct NormalizedPath: Hashable, Sendable`. \
            A generic type declares them conditionally in an extension, like `OrderedDictionary`. A type that cannot \
            be `Hashable` is listed in `Detect.notHashable` with the reason, after review.
            """,
        badExample: "public struct NormalizedPath: CustomStringConvertible {",
        goodExample: "public struct NormalizedPath: Hashable, Sendable, CustomStringConvertible {"
    )

    static let uncheckedSendableExplainsItself = Rule(
        id: "unchecked-sendable-explains-itself",
        title: "An `@unchecked Sendable` conformance has a comment that proves it safe.",
        category: .models,
        rationale: """
            `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only \
            proof left that the type is safe to share (CODING_STANDARDS.md, "Sendable value types"); shared mutable \
            state belongs in an `actor` instead.
            """,
        howToFix: """
            Prefer a value type or an `actor`. If neither fits, put a comment on the declaration that says what \
            guards the mutable state.
            """,
        badExample: "final class Cache: @unchecked Sendable {",
        goodExample: """
            // Every access to `storage` holds `lock`.
            final class Cache: @unchecked Sendable {
            """
    )

    static let noTodoStubs = Rule(
        id: "no-todo-stubs",
        title: "No `fatalError(\"TODO\")`-style stub, in the library or its tests.",
        category: .testing,
        rationale: """
            A stub compiles, so the build and the type checker call the work done, and it crashes the client that \
            reaches it (CONSTRAINTS.md, "Floor"). An unfinished path that a test cannot reach is invisible until a \
            user finds it.
            """,
        howToFix: """
            Implement it, or throw the typed error for the case (`EvaluationError`, `JSONPath.ParseError`) and test \
            that it is thrown. Work left for later goes in a GitHub issue, not in the code.
            """,
        badExample: #"case .jayway: fatalError("TODO: Jayway slices")"#,
        goodExample: "case .jayway: return try JaywayEvaluator(root: root).evaluate(path)"
    )

    static let testsUseSwiftTesting = Rule(
        id: "tests-use-swift-testing",
        title: "Tests use Swift Testing, never XCTest.",
        category: .testing,
        rationale: """
            The suite is Swift Testing only (CODING_STANDARDS.md, "Swift Testing only"): `@Test`, `#expect` and \
            `#require` give one failure message style, parameterised tests over the compliance cases and parallel, \
            randomly ordered runs.
            """,
        howToFix: """
            Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`. A Sextant \
            port translates `XCTAssertEqual` to `#expect(… == …)`.
            """,
        badExample: """
            import XCTest
            final class FilterTest: XCTestCase { func testEquality() { XCTAssertEqual(…) } }
            """,
        goodExample: """
            import Testing
            @Suite struct FilterTest { @Test func equality() { #expect(…) } }
            """
    )

    static let knownIssuesExplainThemselves = Rule(
        id: "known-issues-explain-themselves",
        title: "`withKnownIssue` names the issue that tracks it.",
        category: .testing,
        rationale: """
            A known issue hides a failing expectation. Without a reason and a link, the next reader cannot tell a bug \
            waiting for a fix from a test nobody understood, and nobody removes it once the bug is fixed \
            (CONSTRAINTS.md, "Floor").
            """,
        howToFix: "Pass the reason as the first argument, with the GitHub issue that tracks it.",
        badExample: #"withKnownIssue { #expect(try path.values(in: document) == expected) }"#,
        goodExample: """
            withKnownIssue("Jayway returns the parent for a deep-scan filter (mackoj/swift-jsonpath#12)") {
                #expect(try path.values(in: document) == expected)
            }
            """
    )

    static let testsAreNotDisabled = Rule(
        id: "tests-are-not-disabled",
        title: "No test or suite is `.disabled`.",
        category: .testing,
        rationale: """
            A disabled test still reads as coverage while checking nothing, and compliance cases and Sextant \
            assertions are never dropped to make a change pass (CONSTRAINTS.md, "Floor"). A failing behaviour is \
            either fixed, or asserted as a known issue that names its tracking issue.
            """,
        howToFix: "Fix the code or the test. If the bug must wait, wrap the failing part in `withKnownIssue(\"…#N\")`.",
        badExample: "@Test(.disabled(\"flaky\")) func filterOnDeepScan() throws {",
        goodExample: "@Test func filterOnDeepScan() throws {"
    )
}

/// Every rule, in the order `docs/architecture-rules.md` lists them.
let allRules: [Rule] = [
    .sourcesImportNothing, .libraryPerformsNoIO, .publicTypesAreValues, .publicTypesAreHashableAndSendable,
    .uncheckedSendableExplainsItself, .noTodoStubs, .testsUseSwiftTesting, .knownIssuesExplainThemselves,
    .testsAreNotDisabled,
]
