# swift-jsonpath

[![CI](https://github.com/mackoj/swift-jsonpath/actions/workflows/ci.yml/badge.svg)](https://github.com/mackoj/swift-jsonpath/actions/workflows/ci.yml)

A complete JSONPath implementation in pure Swift — no Foundation, no dependencies — supporting both
the IETF standard and the widely deployed Jayway dialect.

- **RFC 9535** ([JSONPath: Query Expressions for JSON](https://www.rfc-editor.org/rfc/rfc9535)):
  strict grammar, well-typedness checks, the `length` `count` `match` `search` `value` functions with
  I-Regexp. Passes **all 715 cases** of the official
  [JSONPath Compliance Test Suite](https://github.com/jsonpath-standard/jsonpath-compliance-test-suite).
- **Jayway** (the dialect of [Jayway JsonPath](https://github.com/json-path/JsonPath), SMJJSONPath and
  [Sextant](https://github.com/KittyMac/Sextant)): `[?(...)]` filters, loose comparisons, the Jayway
  operators (`=~`, `in`, `nin`, `contains`, `size`, `empty`, `anyof`, …) and path functions
  (`.length()`, `.avg()`, `.concat()`, …). Passes Sextant's **complete test suite**, ported to
  swift-testing, and agrees with Sextant on every input of a differential run except where Sextant
  is buggy.
- Token ranges for **syntax colouring**, in both dialects.
- Normalized paths, and **mutations** driven by paths: replace, remove, map, set by JSON Pointer.
- `JSONValue`: an order-preserving JSON model with a strict RFC 8259 **parser**, a pretty printer
  and an order-preserving **Codable** bridge (`JSONValueDecoder` / `JSONValueEncoder`).
- Swift 6, strict concurrency, everything `Sendable`. Linux, macOS 13+, iOS 16+, tvOS 16+,
  watchOS 9+, visionOS 1+. On Linux it links nothing but the standard library and libm.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/mackoj/swift-jsonpath.git", from: "0.0.1"),
],
targets: [
    .target(name: "MyTool", dependencies: [.product(name: "JSONPath", package: "swift-jsonpath")]),
]
```

## Usage

```swift
import JSONPath

let document = try JSONValue(parsing: """
    {"store": {"book": [
      {"category": "reference", "author": "Nigel Rees", "title": "Sayings of the Century", "price": 8.95},
      {"category": "fiction", "author": "Herman Melville", "title": "Moby Dick", "isbn": "0-553-21311-3", "price": 8.99},
      {"category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord of the Rings", "price": 22.99}
    ], "bicycle": {"color": "red", "price": 19.95}}}
    """)

let cheap = try JSONPath("$.store.book[?@.price < 10].title")
try cheap.values(in: document)         // ["Sayings of the Century", "Moby Dick"]
try cheap.paths(in: document)          // [$['store']['book'][0]['title'], $['store']['book'][1]['title']]
try cheap.nodes(in: document)          // locations + values
try document.query("$..price")         // [8.95, 8.99, 22.99, 19.95]

try JSONPath("$.store.book[?match(@.author, '.*Tolkien')].title").values(in: document)
try JSONPath("$.store.book[?count(@.isbn) > 0].title").values(in: document)
```

### Jayway dialect

```swift
let fiction = try JSONPath("store.book[?(@.category == 'fiction' && @.price > 10)].title", dialect: .jayway)
let pattern = try JSONPath("$..book[?(@.author =~ /.*REES/i)].price", dialect: .jayway)
let count   = try JSONPath("$.store.book.length()", dialect: .jayway)          // [3]
let inList  = try JSONPath("$.store.book[?(@.category in ['fiction'])]", dialect: .jayway)
```

| Feature | `.rfc9535` | `.jayway` |
|---|---|---|
| Names, wildcards, indices, slices, unions, descendants | ✓ | ✓ |
| Filters | `[?expr]`; on objects, tests the members | `[?(expr)]` / `[?expr]`; on objects, tests the object itself |
| Comparisons | strict and typed | loose (`'1' == 1`), plus `===` / `!==` |
| Functions in filters | `length` `count` `match` `search` `value` | same |
| Jayway operators | – | `=~ /re/flags`, `in`, `nin`, `contains`, `all`, `size`, `empty`, `subsetof`, `anyof`, `noneof`, `type`, `exists` |
| Path functions | – | `length()` `size()` `avg()` `sum()` `min()` `max()` `stddev()` `concat()` `append()` `keys()` `first()` `last()` `index(n)` |
| Implicit root (`store.book`) | – | ✓ |
| Slice step `0` | selects nothing | treated as `1` |
| Relation on a missing path | false | error (the filter fails) |

### Mutations

```swift
var copy = document
try copy.replace(JSONPath("$..price"), with: 0)
try copy.remove(JSONPath("$.store.bicycle"))
try copy.map(JSONPath("$..title")) { .string($0.stringValue!.uppercased()) }   // return nil to remove
try copy.set("new", at: JSONPointer("/store/book/0/tag"))
try copy.set(1, at: NormalizedPath(["store", "book", 0, "price"]))
```

### Codable

```swift
struct Book: Codable { let title: String; let price: Double }
let books = try JSONValueDecoder().decode(Book.self, from: JSONPath("$.store.book[*]").values(in: document))
let value = try JSONValue(encoding: books)        // keeps key order
print(value.jsonString(prettyPrinted: true))
```

### Validation and errors

```swift
JSONPath.validate("$.store[?@.price <]")       // a description of the error, or nil when valid

do {
    _ = try JSONPath("$.a[", dialect: .rfc9535)
} catch let error as JSONPath.ParseError {
    print(error.message, error.position)
}
```

`JSONPath.EvaluationError` is thrown for valid paths that fail at evaluation time, such as a Jayway
`avg()` over an empty array.

### Syntax colouring

`JSONPath.tokens(in:dialect:)` splits an expression into runs (root, names, strings, numbers,
operators, function names, brackets, …) with their ranges in the text, for an editor to colour.
It follows the dialect's lexical rules but never rejects text: what it doesn't recognise is a
`.plain` run, so it works on an expression that is still being typed. Validity still comes from
`JSONPath(_:dialect:)`.

```swift
let query = "$[?@.price < 10].title"
for token in JSONPath.tokens(in: query) {
    print(token.kind, query[token.range])    // root $, bracket [, punctuation ?, current @, …
}
```

## Tests

```sh
swift test
```

- `Tests/JSONPathTests/ComplianceTestSuite.swift` runs the JSONPath Compliance Test Suite
  (`Fixtures/cts.json`, BSD-2-Clause).
- `Tests/JSONPathTests/Sextant/` is the test suite of [Sextant](https://github.com/KittyMac/Sextant)
  (MIT, © 2021 Rocco Bowling; derived from Jayway JsonPath via SMJJSONPath), ported to swift-testing.
  Most files are a mechanical translation of the original assertions. Tests that exercise
  Sextant-only APIs (tuples, `Decodable` coercion, in-place `JsonElement` mutation, internal compiler
  types) are adapted to the equivalent `JSONValue` / `JSONPath` APIs, and every adaptation is
  commented where it happens.
- Set `SEXTANT_ORACLE_LOG=/path/to/file.jsonl` to record every (document, path) pair the Sextant
  tests evaluate, for differential testing against Sextant itself.

## License

MIT. See [LICENSE](LICENSE). Test fixtures keep their own licenses, as noted above.
