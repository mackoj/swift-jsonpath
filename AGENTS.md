# Agent notes

`swift-jsonpath` is a Swift library, not an app: JSONPath in both the RFC 9535 and Jayway Dialects, an order-preserving `JSONValue` with its parser and Codable bridge, JSON Pointer and path-driven mutations. Pure Swift with no imports at all; the dependency budget is in `Package.swift`, usage in `README.md`.

Read `CONSTRAINTS.md` before writing code. Do not weaken it to make a change pass.

## Project conventions
- Consult `GLOSSARY.md` for domain terms, `docs/adr/` for decisions and their rationale, and `CODING_STANDARDS.md` for review rules.
- Before the first edit of any task, create a sibling worktree on its own branch: `git worktree add -b <topic> ../swift-jsonpath-<topic> main`, and make every change there. The main checkout stays clean on `main`.
- RFC 9535 is the source of truth for the `rfc9535` Dialect; Jayway JsonPath, as captured by Sextant's tests, is the source of truth for the `jayway` Dialect. Cite the RFC section or the Sextant test a change follows, and record a deliberate difference between Dialects in the README's feature table.

## How to work
- **Plan first.** For a change spanning several files or with more than one reasonable reading, state your assumptions and a short plan (`step → verify: check`), then wait for approval. Name what is unclear instead of guessing.
- **Test first.** Turn the task into a check before coding: a bug gets a failing test that reproduces it; a feature gets a test that exercises it; a refactor keeps every existing test green before and after.
- **Smallest diff.** Every changed line traces to the request. Match the surrounding file's idioms even where you would write it differently. Remove what your change orphans; mention, rather than delete, pre-existing dead code.

## Docs travel with code
`README.md` is the user documentation and DocC comments are the API reference (Swift Package Index builds docs for `JSONPath`, see `.spi.yml`). In the same change as any API or behaviour change:
- Update the doc comment on every public declaration you touch.
- Update every README section, example and table the change affects (`grep -n "<Symbol>" README.md`), including the Dialect feature table.
- Keep README snippets compiling: `Tests/JSONPathTests/ReadmeTests.swift` mirrors them, so a changed snippet changes its test.

## Build and test
- `swift build` and `swift test`; one test with `swift test --filter <Suite>/<test>`. Pipe through `xcsift` (configured in `.xcsift.toml`) for compact errors.
- CI (`.github/workflows/ci.yml`) runs macOS and Linux on Swift 6.0, 6.1 and 6.2: code must compile on 6.0 with only the standard library.
- Format before handing back Swift changes: `swift-format format --in-place --parallel --recursive Sources Tests Package.swift` (config in `.swift-format`). Use the Swift 6.3 toolchain's swift-format (`swiftly run swift-format … +6.3`): the format check runs 6.3, and other versions wrap lines differently.
- Pull requests also run `.github/workflows/soundness.yml`: swiftlang's soundness checks (format, DocC with warnings as errors, API breakage against the base branch, YAML lint, shellcheck, broken symlinks) plus actionlint and zizmor on the workflows. A deliberate API break is called out in the pull request.
- For a differential run against Sextant, set `SEXTANT_ORACLE_LOG` as described in the README's Tests section.

## Agent skills

### Issue tracker
Issues and specifications live in GitHub Issues for mackoj/swift-jsonpath. See `docs/agents/issue-tracker.md`.

### Triage labels
Use the five default triage labels. See `docs/agents/triage-labels.md`.

### Domain docs
Single-context layout: root `GLOSSARY.md` and `docs/adr/`. See `docs/agents/domain.md`.
