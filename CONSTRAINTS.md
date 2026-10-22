# Constraints

Last reviewed: 2026-10-22

## Floor

- No new checker suppressions (`swiftlint:disable`, `@available(*, deprecated)` to silence warnings), disabled or skipped tests (`.disabled`, `withKnownIssue` without a linked issue), `fatalError("TODO")`-style stubs, or secrets in source.
- No deleted tests or removed assertions without a reason in the commit message. Compliance test suite cases and Sextant assertions are never dropped to make a change pass.
- Fixtures under `Tests/*/Fixtures/` stay byte-identical to upstream.
- Do not weaken this file to make a change pass.

## Enforced checks

Run these before handing back a code change; each must pass.

| Dimension | Rule | Checked by |
|-----------|------|------------|
| Diff integrity | 0 whitespace errors | `git diff --check main` |
| Compilation | 0 errors, debug and release | `swift build --build-tests` and `swift build -c release` |
| Behaviour | 0 failing tests, including all 715 compliance cases, the Sextant suite and README examples | `swift test` |
| Formatting | 0 changes from formatting, 0 lint findings, with swift-format 6.3 | `swift-format lint --strict --parallel --recursive Sources Tests Package.swift` |
| Public API | 0 breaking changes against the base branch, unless intended and called out in the pull request | `swift package diagnose-api-breaking-changes main` |
| Documentation | 0 DocC warnings for the `.spi.yml` targets | Soundness workflow's documentation check (CI) |
| Workflows and YAML | 0 findings | `actionlint`, `zizmor .github/workflows` and `yamllint --strict .` |
| Dependency budget | `Sources/` imports nothing: no Foundation, FoundationEssentials or packages | `! grep -rnE '^\s*(@_exported )?import ' Sources` |

Linux is the platform most likely to break (no Objective-C Foundation, older toolchains): CI runs Swift 6.0, 6.1 and 6.2 in Linux containers. When a change touches number formatting, regexes, Unicode or platform guards, say whether you checked it on Linux (for example `docker run --rm -v "$PWD":/src -w /src swift:6.0 swift test`) or leave it to CI.

## Exceptions

| ID | Rule | Path | Reason | Owner | Expires |
|----|------|------|--------|-------|---------|
