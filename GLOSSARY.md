# swift-jsonpath

JSONPath for Swift in two Dialects, with the JSON model it queries. Terms follow [RFC 9535](https://www.rfc-editor.org/rfc/rfc9535) unless marked Jayway; the Swift type is in parentheses.

## Paths and Dialects

**Path** (`JSONPath`):
A parsed JSONPath query string together with its Dialect. Constructing one parses it; a bad path fails then, not at evaluation.
_Avoid_: expression (that is the source text, `JSONPath.expression`), selector (that is one part of a Segment)

**Dialect** (`JSONPath.Dialect`):
Which JSONPath language a Path is written in: `rfc9535` (strict, the default) or `jayway` (the Goessner-derived dialect of Jayway JsonPath, SMJJSONPath and Sextant). The README's feature table is the authoritative list of differences.
_Avoid_: flavour, mode, version

**Root / current node**:
`$`, the queried document, and `@`, the node a Filter is testing. Jayway also accepts an implicit root (`store.book`).

**Segment**:
One step of a Path: a child segment (`.name`, `[…]`) or a descendant segment (`..`), each holding one or more Selectors. Jayway adds a trailing Path function as a segment.
_Avoid_: step, token

**Selector**:
What a Segment picks from each input node: a name, wildcard, index, slice or Filter.
_Avoid_: query, path

**Filter**:
A Selector (`[?…]`, Jayway `[?(…)]`) keeping the children for which a logical expression holds. Under `rfc9535` it tests an object's members; under `jayway` it tests the object itself.
_Avoid_: predicate, condition

**Function extension**:
An RFC 9535 function usable inside a Filter: `length`, `count`, `match`, `search`, `value`. Its argument and result types are checked at parse time (well-typedness).
_Avoid_: Path function

**Path function** (Jayway):
A function applied at the end of a Path to the selected values, such as `.length()`, `.avg()` or `.concat()`.
_Avoid_: Function extension, method

**Jayway operator**:
A Filter operator outside RFC 9535: `=~`, `in`, `nin`, `contains`, `size`, `empty`, `anyof`, …, plus strict `===` / `!==`.

**Singular path** (`JSONPath.isSingular`):
A Path that can select at most one node: RFC 9535 "singular query", Jayway "definite path".

**I-Regexp**:
RFC 9485's interoperable regex subset, which `match` and `search` use under `rfc9535`.
_Avoid_: regex (alone, when the Dialect matters)

## Results

**Node** (`JSONPath.Node`):
One selected value together with its Normalized path.

**Nodelist**:
The ordered result of evaluating a Path: its Nodes, exposed as `nodes(in:)`, `values(in:)` or `paths(in:)`. An empty Nodelist is a valid result, not an error.
_Avoid_: matches, result set

**Normalized path** (`NormalizedPath`):
RFC 9535's canonical, unique path to one Node, such as `$['store']['book'][0]`.
_Avoid_: JSON Pointer, location string

**JSON Pointer** (`JSONPointer`):
RFC 6901's `/`-separated reference to a single location, used to set a value at an exact place.
_Avoid_: Path, Normalized path

**Mutation**:
A change to a `JSONValue` driven by a Path or pointer: `replace`, `remove`, `map` (returning `nil` removes) or `set`. Failures are `JSONValue.MutationError`.
_Avoid_: update, patch (that is RFC 6902)

## JSON model

**JSONValue** (`JSONValue`):
The library's order-preserving JSON value, with a strict RFC 8259 parser and a pretty printer.
_Avoid_: JSON (alone), Any, element (Sextant's `JsonElement`)

**Codable bridge** (`JSONValueDecoder`, `JSONValueEncoder`):
Conversion between Swift `Codable` types and `JSONValue`, exposing and keeping object keys in document order, unlike `JSONDecoder`.

## Testing

**Compliance test suite**:
The official RFC 9535 conformance cases in `Fixtures/cts.json`, all 715 of which pass.
_Avoid_: CTS (in prose without first spelling it out)

**Sextant port**:
Sextant's test suite translated to Swift Testing under `Tests/JSONPathTests/Sextant/`: the reference for the `jayway` Dialect. Adaptations to this library's API are commented in place.

**Differential run**:
Recording every (document, Path) pair the Sextant port evaluates, via `SEXTANT_ORACLE_LOG`, to compare results with Sextant itself.
