import JSONPath
import Testing

@Suite("JSON parser")
struct JSONParserTests {
    @Test func parsesAndPreservesOrder() throws {
        let value = try JSONValue(
            parsing: #"{"z": 1, "a": [true, false, null], "m": {"x": 1.5, "y": "line\n\u00e9\ud834\udd1e"}}"#)
        #expect(value.objectValue?.keys == ["z", "a", "m"])
        #expect(value["a"] == [true, false, nil])
        #expect(value["m"]?["x"] == .number(1.5))
        #expect(value["m"]?["y"] == "line\n\u{e9}\u{1D11E}")
        #expect(
            value.jsonString == "{\"z\":1,\"a\":[true,false,null],\"m\":{\"x\":1.5,\"y\":\"line\\n\u{e9}\u{1D11E}\"}}")
    }

    @Test func escapesNextToMultibyteText() throws {
        // Given strings mixing raw UTF-8, escapes at either end, and an escaped key
        let text = #"{"k\u00e9y": "é\"日本\\", "only": "\n\t", "edge": "\u00e9é", "plain": "日本語"}"#

        // When parsed, and when invalid UTF-8 is parsed from bytes
        let value = try JSONValue(parsing: text)
        let repaired = try JSONValue(parsing: [0x22, 0x61, 0xC3, 0x5C, 0x6E, 0xFF, 0x22] as [UInt8])

        // Then every string is unescaped, and invalid bytes become U+FFFD
        #expect(value.objectValue?.keys == ["k\u{e9}y", "only", "edge", "plain"])
        #expect(value["k\u{e9}y"] == "\u{e9}\"日本\\")
        #expect(value["only"] == "\n\t")
        #expect(value["edge"] == "\u{e9}\u{e9}")
        #expect(value["plain"] == "日本語")
        #expect(repaired == "a\u{FFFD}\n\u{FFFD}")
    }

    @Test func printsEscapesNextToMultibyteText() throws {
        // Given strings with every escape next to multibyte text, as a key and as a value
        let value: JSONValue = ["é\"k": "\u{01}日\\\u{1F}\t👍\u{08}\u{0C}\r"]

        // When printed compactly and pretty
        let compact = value.jsonString
        let pretty = value.jsonString(prettyPrinted: true)

        // Then only the ASCII escapes change, and both forms parse back to the value
        #expect(compact == #"{"é\"k":"\u0001日\\\u001f\t👍\b\f\r"}"#)
        #expect(pretty == "{\n  " + #""é\"k": "\u0001日\\\u001f\t👍\b\f\r""# + "\n}")
        #expect(try JSONValue(parsing: compact) == value)
        #expect(try JSONValue(parsing: pretty) == value)
    }

    @Test func numbers() throws {
        #expect(try JSONValue(parsing: "0") == 0)
        #expect(try JSONValue(parsing: "-12") == -12)
        #expect(try JSONValue(parsing: "1e3") == .number(1000))
        #expect(try JSONValue(parsing: "9223372036854775807") == .integer(Int.max))
        #expect(try JSONValue(parsing: "-9223372036854775808") == .integer(Int.min))
        #expect(try JSONValue(parsing: "-9223372036854775809") == .number(-9_223_372_036_854_775_809.0))
        #expect(try JSONValue(parsing: "-0") == .integer(0))
        #expect(try JSONValue(parsing: "18446744073709551615") == .number(18_446_744_073_709_551_615.0))
    }

    @Test(arguments: [
        "", "01", "1.", ".5", "+1", "[1,]", "{\"a\":1,}", "'a'", "\"\u{01}\"", "\"\\x\"", "\"\\ud800\"", "nul", "[1] 2",
        "{\"a\" 1}",
    ])
    func rejectsInvalidJSON(_ text: String) {
        #expect(throws: JSONValue.ParseError.self) { try JSONValue(parsing: text) }
    }

    @Test func duplicateKeysKeepLastValue() throws {
        #expect(try JSONValue(parsing: #"{"a": 1, "b": 2, "a": 3}"#).jsonString == #"{"a":3,"b":2}"#)
    }
}

@Suite("JSONPath API")
struct JSONPathAPITests {
    @Test func patternsReusedInOneQueryKeepTheirOwnFlagsAndSemantics() throws {
        // Given names that differ in case and in what surrounds the pattern
        let document: JSONValue = [["n": "Ab"], ["n": "ab"], ["n": "xab"], ["n": 1]]

        // When one query uses a pattern with and without flags, or under both match and search
        let jayway = try JSONPath(#"$[?(@.n =~ /ab/i || @.n =~ /ab/)].n"#, dialect: .jayway).values(in: document)
        let jaywayCaseSensitive = try JSONPath(#"$[?(@.n =~ /ab/ && !(@.n =~ /AB/i))].n"#, dialect: .jayway)
            .values(in: document)
        let rfc = try JSONPath("$[?match(@.n, 'ab') || search(@.n, 'ab')].n").values(in: document)
        let rfcWhole = try JSONPath("$[?match(@.n, 'ab') && search(@.n, 'ab')].n").values(in: document)

        // Then each use keeps its own flags, and match stays whole-string while search does not
        #expect(jayway == ["Ab", "ab", "xab"])
        #expect(jaywayCaseSensitive == [])
        #expect(rfc == ["ab", "xab"])
        #expect(rfcWhole == ["ab"])
    }

    static let store = try! JSONValue(
        parsing: """
            {"store": {"book": [
              {"category": "reference", "author": "Nigel Rees", "price": 8.95},
              {"category": "fiction", "author": "Evelyn Waugh", "price": 12.99},
              {"category": "fiction", "author": "Herman Melville", "isbn": "0-553-21311-3", "price": 8.99}
            ], "bicycle": {"color": "red", "price": 19.95}}}
            """)

    @Test func nodesValuesAndPaths() throws {
        let path = try JSONPath("$.store.book[?@.price < 10].author")
        #expect(try path.values(in: Self.store) == ["Nigel Rees", "Herman Melville"])
        #expect(
            try path.paths(in: Self.store).map(\.description) == [
                "$['store']['book'][0]['author']", "$['store']['book'][2]['author']",
            ])
        #expect(try path.paths(in: Self.store).first?.jsonPointer.description == "/store/book/0/author")
        #expect(try path.matches(Self.store))
        #expect(try JSONPath("$.nope").firstValue(in: Self.store) == nil)
        #expect(try Self.store.query("$..price").count == 4)
    }

    @Test func dialectDifferences() throws {
        let object: JSONValue = ["a": 1, "b": ["a": 2]]
        // A filter on an object: RFC 9535 tests the members, Jayway tests the object itself.
        #expect(try JSONPath("$[?@.a]").values(in: object) == [["a": 2]])
        #expect(try JSONPath("$[?(@.a)]", dialect: .jayway).values(in: object) == [object])
        // Loose vs strict comparisons.
        let list: JSONValue = [["v": "1"], ["v": 1]]
        #expect(try JSONPath("$[?@.v == 1]").values(in: list).count == 1)
        #expect(try JSONPath("$[?(@.v == 1)]", dialect: .jayway).values(in: list).count == 2)
        // Slice step 0.
        #expect(try JSONPath("$[::0]").values(in: [1, 2]) == [])
        #expect(try JSONPath("$[::0]", dialect: .jayway).values(in: [1, 2]) == [1, 2])
        // Jayway-only syntax.
        #expect(throws: JSONPath.ParseError.self) { try JSONPath("$.numbers.length()") }
        #expect(throws: JSONPath.ParseError.self) { try JSONPath("store.book") }
        #expect(throws: JSONPath.ParseError.self) { try JSONPath("$[?(@.a in [1,2])]") }
        #expect(try JSONPath("store.book[0].author", dialect: .jayway).values(in: Self.store) == ["Nigel Rees"])
    }

    @Test func rfcFunctionsWorkInBothDialects() throws {
        let doc: JSONValue = ["pets": [["name": "Rex"], ["name": "Tom"]]]
        // Jayway applies the filter to the root object itself – the Arazzo spec's
        // `$[?count(@.pets) > 0]` example relies on this.
        #expect(try JSONPath("$[?count(@.pets[*]) > 1]", dialect: .jayway).values(in: doc).count == 1)
        #expect(try JSONPath("$.pets[?match(@.name, 'R.*')].name").values(in: doc) == ["Rex"])
        #expect(try JSONPath("$.pets[?search(@.name, 'o')].name", dialect: .jayway).values(in: doc) == ["Tom"])
        #expect(try JSONPath("$[?length(@) == 2]").values(in: doc).count == 1)
    }

    @Test func descriptions() throws {
        #expect(
            try JSONPath("$.store.book[0,1]['author', \"price\"]").description
                == "$['store']['book'][0, 1]['author', 'price']")
        #expect(
            try JSONPath("$..book[?@.price<10 && (@.isbn || !@.author)]").description
                == "$..['book'][?@['price'] < 10 && (@['isbn'] || !@['author'])]")
        #expect(try JSONPath("$.a.b", dialect: .jayway).description == "$['a']['b']")
        #expect(try JSONPath("$.a").isSingular)
        #expect(try !JSONPath("$.a[*]").isSingular)
    }

    @Test func parseErrorsCarryPositions() {
        do {
            _ = try JSONPath("$.store[?@.price <]")
            Issue.record("expected an error")
        } catch let error as JSONPath.ParseError {
            #expect(error.position > 0)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(JSONPath.validate("$.ok") == nil)
        #expect(JSONPath.validate("$.") != nil)
    }

    @Test func functionErrorsAreEvaluationErrors() {
        #expect(throws: JSONPath.EvaluationError.self) {
            try JSONPath("$.empty.avg()", dialect: .jayway).values(in: ["empty": []])
        }
    }

    @Test func pathsAreSendableAndHashable() throws {
        let a = try JSONPath("$.a")
        let b = try JSONPath("$['a']")
        #expect(a == b)  // same query, different spelling
        #expect(Set([a, b]).count == 1)
    }
}

@Suite("Any Dialect")
struct AnyDialectTests {
    @Test func anRFCOnlyPathIsRFC9535() throws {
        // Given a union with a wildcard, which only RFC 9535 parses
        #expect(JSONPath.validate("$[*, 0]", dialect: .jayway) != nil)

        // When
        let path = try JSONPath(anyDialect: "$[*, 0]")

        // Then
        #expect(path.dialect == .rfc9535)
        #expect(try path.values(in: [1, 2]) == [1, 2, 1])
    }

    @Test func aJaywayOnlyPathIsJayway() throws {
        // Given a Jayway path function, which RFC 9535 rejects
        #expect(JSONPath.validate("$.numbers.length()") != nil)

        // When
        let path = try JSONPath(anyDialect: "$.numbers.length()")

        // Then
        #expect(path.dialect == .jayway)
        #expect(try path.values(in: ["numbers": [1, 2, 3]]) == [3])
    }

    @Test func aPathValidInBothDialectsIsRFC9535() throws {
        // Given a comparison both Dialects parse, where Jayway's loose equality selects more
        let list: JSONValue = [["v": "1"], ["v": 1]]

        // When
        let path = try JSONPath(anyDialect: "$[?@.v == 1]")

        // Then
        #expect(path.dialect == .rfc9535)
        #expect(try path.values(in: list) == [["v": 1]])
    }

    @Test func aPathInvalidInBothDialectsThrowsTheRFC9535Error() {
        // Given a path neither Dialect parses, each with its own message
        let rfcError = JSONPath.ParseError(message: "Unexpected end of query", position: 4)
        #expect(JSONPath.validate("$.a[") == rfcError.message)
        let jaywayMessage = JSONPath.validate("$.a[", dialect: .jayway)
        #expect(jaywayMessage != nil && jaywayMessage != rfcError.message)

        // When / Then
        #expect(throws: rfcError) {
            try JSONPath(anyDialect: "$.a[")
        }
    }
}

@Suite("Mutations")
struct MutationTests {
    @Test func setAtPointer() throws {
        var value: JSONValue = ["items": [1, 2], "meta": [:]]
        try value.set(3, at: JSONPointer("/items/-"))
        try value.set(0, at: JSONPointer("/items/0"))
        try value.set("x", at: JSONPointer("/meta/name"))
        try value.set(9, at: JSONPointer("/items/3"))
        #expect(value == ["items": [0, 2, 3, 9], "meta": ["name": "x"]])
        #expect(throws: JSONValue.MutationError.self) { try value.set(1, at: JSONPointer("/missing/deep")) }
        #expect(throws: JSONValue.MutationError.self) { try value.set(1, at: JSONPointer("/items/10")) }
        try value.set("root", at: JSONPointer.root)
        #expect(value == "root")
    }

    @Test func removeKeepsIndicesConsistent() throws {
        var value: JSONValue = [0, 1, 2, 3, 4, 5]
        let removed = try value.remove(JSONPath("$[?@ < 3]"))
        #expect(removed == 3)
        #expect(value == [3, 4, 5])
    }

    @Test func mutationLeavesOtherCopiesUnchanged() throws {
        // Given a document with nested arrays and objects, and a copy of it
        let books: [JSONValue] = (0..<100).map { ["price": .integer($0), "tags": ["a", .integer($0)]] }
        let original: JSONValue = ["store": ["book": .array(books)]]
        var copy = original

        // When the copy is mutated at many locations, deep and shallow
        let replaced = try copy.replace(JSONPath("$..price"), with: 0)
        let removed = try copy.remove(JSONPath("$.store.book[?@.tags[1] >= 50]"))
        try copy.set("x", at: JSONPointer("/store/book/0/tags/0"))

        // Then the copy has every change and the original none
        #expect(replaced == 100)
        #expect(removed == 50)
        #expect(copy["store"]?["book"]?.arrayValue?.count == 50)
        #expect(copy["store"]?["book"]?[49] == ["price": 0, "tags": ["a", 49]])
        #expect(copy["store"]?["book"]?[0]?["tags"] == ["x", 0])
        #expect(original == ["store": ["book": .array(books)]])
        #expect(original["store"]?["book"]?[99]?["price"] == 99)
    }

    @Test func normalizedPathSubscriptAndOrdering() throws {
        let value: JSONValue = ["a": [["b": 1]]]
        let path: NormalizedPath = ["a", 0, "b"]
        #expect(value[path] == 1)
        #expect(path.description == "$['a'][0]['b']")
        #expect(NormalizedPath(["a", 1]) > NormalizedPath(["a", 0]))
        #expect(NormalizedPath(["it's"]).description == #"$['it\'s']"#)
    }
}

@Suite("Ordered dictionary")
struct OrderedDictionaryTests {
    @Test(arguments: [3, 20])
    func keepsOrderAndFindsEveryKeyAcrossSizes(count: Int) {
        // Given members inserted in a scrambled order, past the linear-search limit for the larger count
        let names = (0..<count).map { "k\(($0 * 7) % count)" }
        var dictionary = OrderedDictionary<String, Int>()
        for (index, name) in names.enumerated() { dictionary[name] = index }

        // When members are updated and removed, shrinking back across the limit
        dictionary[names[0]] = -1
        let removed = names.prefix(count - 2).dropFirst()
        for name in removed { dictionary.removeValue(forKey: name) }

        // Then order, lookups and both arrays agree
        let kept = [names[0]] + names.suffix(2)
        #expect(dictionary.keys == kept)
        #expect(dictionary.values == [-1, count - 2, count - 1])
        #expect(kept.map { dictionary[$0] } == [-1, count - 2, count - 1])
        #expect(removed.allSatisfy { dictionary[$0] == nil && !dictionary.contains(key: $0) })
    }

    @Test(arguments: [3, 20])
    func equalityAndHashingIgnoreOrder(count: Int) {
        // Given the same members in two orders
        let pairs = (0..<count).map { ("k\($0)", $0) }
        let forward = OrderedDictionary(pairs)
        let backward = OrderedDictionary(pairs.reversed())

        // Then they are equal and hash alike, and a changed value is not equal
        #expect(forward == backward)
        #expect(forward.hashValue == backward.hashValue)
        var changed = backward
        changed["k0"] = -1
        #expect(forward != changed)
    }
}
