# Coding standards

Read during review. Each rule is a judgement call; mechanical rules live in `CONSTRAINTS.md`.

## Simplicity

- **Boring code.** The minimum that solves the stated problem: no options, parameters or variants nobody asked for, no protocol or abstraction with a single user. A plain `switch` over an AST enum beats a pattern. If it could be a quarter of the length, it should be.
- **Surgical diffs.** Every changed line traces to the request; adjacent code, comments and formatting stay as they were. Orphans the change creates are removed in the same change.
- **Matches its surroundings.** New code follows the naming, comment density and idioms of the file it lands in (e.g. `Hashable, Sendable` on every public type, `OrderedDictionary` for object members).

## Standard fidelity

- **The standard decides.** `rfc9535` behaviour follows RFC 9535 to the letter, including well-typedness errors at parse time; `jayway` behaviour follows Jayway JsonPath as Sextant's tests capture it. Where Sextant is buggy, the divergence is commented in the test.
- **Dialects stay separate.** A Jayway leniency never leaks into `rfc9535` parsing or evaluation, and the reverse. Shared code is shared only where both Dialects agree.
- **Order is preserved.** Object member order survives parsing, querying, mutation, printing and the Codable bridge.
- **Domain language.** Types, docs and messages use the terms in `GLOSSARY.md`, not the words under _Avoid_. A new concept gets a glossary entry in the same change.

## Compile-time safety

- **Make misuse unrepresentable.** Parsed text becomes a typed AST, not a string checked later; distinct kinds of path (`JSONPath`, `NormalizedPath`, `JSONPointer`) stay distinct types.
- **Failures are typed values.** Parsing throws `JSONPath.ParseError` with a position; evaluation throws `EvaluationError`; mutation throws `JSONValue.MutationError`. An optional return is for genuine absence (`firstValue(in:)`), not to hide why something failed. Errors name the offending expression or location, never echo a whole document.
- **Sendable value types.** Public types are `struct`/`enum`, `Sendable` and `Hashable`, so tests compare whole values. Shared mutable state, if it ever appears, lives in an `actor`; `@unchecked Sendable` needs a comment proving safety.
- **Pure library.** Callers pass data in; the library performs no I/O, reads no clock or environment, and touches no singletons.
- **Standard library only.** Anything Foundation would provide (number formatting, regexes, Unicode handling) is written against the standard library; platform differences go behind `#if canImport(…)` / `#if os(…)`.

## Docs

- **Docs in the same change.** Public API or behaviour changes update the DocC comment, every affected README section or table, and `ReadmeTests` (see `AGENTS.md`). A stale doc is a defect: wrong documentation is worse than none.
- **Doc comments explain why.** Document constraints, RFC references and Dialect differences; skip restating names and signatures.

## Tests

- **Swift Testing only.** `@Suite`, `@Test`, `#expect`, `#require`; no XCTest.
- **Given / When / Then.** Each test has those three phases (comments when the test is longer than a few lines) and asserts one behaviour; related `#expect`s sit together under _Then_.
- **Isolated.** Each test builds its own values; no shared mutable state, so the default random order always passes. The Sextant oracle log in `Tests/JSONPathTests/Support/` is opt-in test tooling, not a pattern for new tests.
- **Conformance suites as fixtures.** The compliance test suite is copied unmodified with its licence noted in `Fixtures/README.md`. Sextant ports stay a mechanical translation; an adaptation is commented where it happens.
