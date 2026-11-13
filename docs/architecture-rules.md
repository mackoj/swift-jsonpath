# Architecture rules

The mechanical part of `CODING_STANDARDS.md` and `CONSTRAINTS.md`, enforced by the `Architecture/` package with [swift-llm-check](https://github.com/mackoj/swift-llm-check): `swift test --package-path Architecture` (macOS). Generated from its rules; do not edit by hand.

## platforms

The dependency budget. Read before you add an `import` to `Sources`.

### `Sources` imports nothing: no Foundation, no FoundationEssentials, no package, no libc.

`sources-import-nothing`: swift-jsonpath is pure Swift with no imports at all (CONSTRAINTS.md, "Dependency budget"; CODING_STANDARDS.md, "Standard library only"). Every client, on every platform, gets the library without Foundation's size or its differences between Darwin and Linux. One import is a dependency for all of them.

**How to fix:** Write it against the standard library, as the number formatting, regexes and Unicode handling already are. Platform differences go behind `#if os(…)` without importing anything; `rounded()` and `squareRoot()` already link libm in `Package.swift`. A new dependency is a decision for the maintainer, recorded in `Package.swift` and CONSTRAINTS.md first.

Bad:

```swift
import Foundation
let text = String(format: "%.17g", number)
```

Good:

```swift
// Sources/JSONPath/JSONValue.swift: number formatting written against the standard library.
let text = number.description
```

## purity

The library is pure. Read before you print, read input or reach for randomness.

### The library prints nothing, reads no input or arguments and uses no randomness.

`library-performs-no-io`: swift-jsonpath is a pure library (CODING_STANDARDS.md, "Pure library"): callers pass data in and get values back, so the same query on the same document gives the same result on every platform and in every test. `print` writes to a host's standard output, `readLine` and `CommandLine` read the process's, and `random`, `shuffled` and `randomElement` make results differ from one run to the next.

**How to fix:** Return the value, or report a problem as a thrown `JSONPath.ParseError`, `EvaluationError` or `JSONValue.MutationError`. Take anything the caller knows as a parameter.

Bad:

```swift
print("unknown function \(name)")
let pick = values.randomElement()
```

Good:

```swift
throw JSONPath.ParseError(message: "unknown function \(name)", position: start)
```

## models

Public types and concurrency. Read before you add or change a public type.

### A public type is a `struct` or an `enum`, never a `class` or an `actor`.

`public-types-are-values`: Public types are values (CODING_STANDARDS.md, "Sendable value types"): a `JSONValue` or a `JSONPath` copied into another task cannot change under the caller, and tests compare whole values. A public class shares mutable state with every holder; turning it into a struct later breaks clients.

**How to fix:** Make it a `struct` or an `enum`. Reference storage that a value type needs stays internal, like `ObjectStorage` in `JSONValueCoding.swift`.

Bad:

```swift
public final class JSONPointer {
```

Good:

```swift
public struct JSONPointer: Hashable, Sendable {
```

### A public struct or enum is declared `Sendable`, and `Hashable` unless it holds `any Sendable`.

`public-types-are-hashable-and-sendable`: Public types are `Sendable` and `Hashable` (CODING_STANDARDS.md, "Sendable value types"): `Sendable` lets clients share a parsed path or a document across tasks under Swift 6, and `Hashable` lets tests compare whole values and clients use them as keys. A missing conformance is a source break to add later, since a client cannot add it. `JSONValueDecoder` and `JSONValueEncoder` are `Sendable` only: their `userInfo` holds `any Sendable` values, which cannot be compared.

**How to fix:** Declare both on the type itself, like its neighbours: `public struct NormalizedPath: Hashable, Sendable`. A generic type declares them conditionally in an extension, like `OrderedDictionary`. A type that cannot be `Hashable` is listed in `Detect.notHashable` with the reason, after review.

Bad:

```swift
public struct NormalizedPath: CustomStringConvertible {
```

Good:

```swift
public struct NormalizedPath: Hashable, Sendable, CustomStringConvertible {
```

### An `@unchecked Sendable` conformance has a comment that proves it safe.

`unchecked-sendable-explains-itself`: `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only proof left that the type is safe to share (CODING_STANDARDS.md, "Sendable value types"); shared mutable state belongs in an `actor` instead.

**How to fix:** Prefer a value type or an `actor`. If neither fits, put a comment on the declaration that says what guards the mutable state.

Bad:

```swift
final class Cache: @unchecked Sendable {
```

Good:

```swift
// Every access to `storage` holds `lock`.
final class Cache: @unchecked Sendable {
```

## testing

Swift Testing, no silenced tests and no stubs. Read before you add, skip or mark a test.

### No `fatalError("TODO")`-style stub, in the library or its tests.

`no-todo-stubs`: A stub compiles, so the build and the type checker call the work done, and it crashes the client that reaches it (CONSTRAINTS.md, "Floor"). An unfinished path that a test cannot reach is invisible until a user finds it.

**How to fix:** Implement it, or throw the typed error for the case (`EvaluationError`, `JSONPath.ParseError`) and test that it is thrown. Work left for later goes in a GitHub issue, not in the code.

Bad:

```swift
case .jayway: fatalError("TODO: Jayway slices")
```

Good:

```swift
case .jayway: return try JaywayEvaluator(root: root).evaluate(path)
```

### Tests use Swift Testing, never XCTest.

`tests-use-swift-testing`: The suite is Swift Testing only (CODING_STANDARDS.md, "Swift Testing only"): `@Test`, `#expect` and `#require` give one failure message style, parameterised tests over the compliance cases and parallel, randomly ordered runs.

**How to fix:** Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`. A Sextant port translates `XCTAssertEqual` to `#expect(… == …)`.

Bad:

```swift
import XCTest
final class FilterTest: XCTestCase { func testEquality() { XCTAssertEqual(…) } }
```

Good:

```swift
import Testing
@Suite struct FilterTest { @Test func equality() { #expect(…) } }
```

### `withKnownIssue` names the issue that tracks it.

`known-issues-explain-themselves`: A known issue hides a failing expectation. Without a reason and a link, the next reader cannot tell a bug waiting for a fix from a test nobody understood, and nobody removes it once the bug is fixed (CONSTRAINTS.md, "Floor").

**How to fix:** Pass the reason as the first argument, with the GitHub issue that tracks it.

Bad:

```swift
withKnownIssue { #expect(try path.values(in: document) == expected) }
```

Good:

```swift
withKnownIssue("Jayway returns the parent for a deep-scan filter (mackoj/swift-jsonpath#12)") {
    #expect(try path.values(in: document) == expected)
}
```

### No test or suite is `.disabled`.

`tests-are-not-disabled`: A disabled test still reads as coverage while checking nothing, and compliance cases and Sextant assertions are never dropped to make a change pass (CONSTRAINTS.md, "Floor"). A failing behaviour is either fixed, or asserted as a known issue that names its tracking issue.

**How to fix:** Fix the code or the test. If the bug must wait, wrap the failing part in `withKnownIssue("…#N")`.

Bad:

```swift
@Test(.disabled("flaky")) func filterOnDeepScan() throws {
```

Good:

```swift
@Test func filterOnDeepScan() throws {
```
