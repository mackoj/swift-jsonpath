import JSONPath
import Testing

@Suite("Token ranges")
struct TokenTests {
    /// `kind text` for each token, to compare runs at a glance.
    static func describe(_ expression: String, _ dialect: JSONPath.Dialect = .rfc9535) -> [String] {
        JSONPath.tokens(in: expression, dialect: dialect).map { "\($0.kind) \(expression[$0.range])" }
    }

    /// The runs are in order and do not overlap, and every character outside them is a blank.
    static func coversEveryNonBlank(_ expression: String, _ dialect: JSONPath.Dialect) -> Bool {
        var cursor = expression.startIndex
        for token in JSONPath.tokens(in: expression, dialect: dialect) {
            guard cursor <= token.range.lowerBound, !token.range.isEmpty else { return false }
            guard expression[cursor..<token.range.lowerBound].allSatisfy({ " \t\n\r".contains($0) }) else {
                return false
            }
            cursor = token.range.upperBound
        }
        return expression[cursor...].allSatisfy { " \t\n\r".contains($0) }
    }

    @Test(arguments: JSONPath.Dialect.allCases)
    func filterQuery(_ dialect: JSONPath.Dialect) {
        #expect(
            Self.describe("$[?(@.status == 'available' && @.price < 200)].id", dialect) == [
                "root $", "bracket [", "punctuation ?", "bracket (", "current @", "punctuation .", "name status",
                "operator ==", "string 'available'", "operator &&", "current @", "punctuation .", "name price",
                "operator <", "number 200", "bracket )", "bracket ]", "punctuation .", "name id",
            ])
    }

    @Test func selections() {
        #expect(
            Self.describe("$..book[0, -1]['title', \"isbn\"][1:5:2].*") == [
                "root $", "punctuation ..", "name book", "bracket [", "number 0", "punctuation ,", "number -1",
                "bracket ]", "bracket [", "name 'title'", "punctuation ,", "name \"isbn\"", "bracket ]", "bracket [",
                "number 1", "punctuation :", "number 5", "punctuation :", "number 2", "bracket ]", "punctuation .",
                "wildcard *",
            ])
    }

    @Test func functionsAndLiterals() {
        #expect(
            Self.describe("$[?length(@.tags) >= 2 && match(@.name, 'R.*') || !@.x || @.y == null]") == [
                "root $", "bracket [", "punctuation ?", "function length", "bracket (", "current @", "punctuation .",
                "name tags", "bracket )", "operator >=", "number 2", "operator &&", "function match", "bracket (",
                "current @", "punctuation .", "name name", "punctuation ,", "string 'R.*'", "bracket )",
                "operator ||", "operator !", "current @", "punctuation .", "name x", "operator ||", "current @",
                "punctuation .", "name y", "operator ==", "keyword null", "bracket ]",
            ])
    }

    @Test func jaywayExtras() {
        #expect(
            Self.describe("$.store.book[?(@.author =~ /.*rees/i && @.tags anyof ['a', 'b'])].price.avg()", .jayway)
                == [
                    "root $", "punctuation .", "name store", "punctuation .", "name book", "bracket [",
                    "punctuation ?", "bracket (", "current @", "punctuation .", "name author", "operator =~",
                    "regex /.*rees/i", "operator &&", "current @", "punctuation .", "name tags", "operator anyof",
                    "bracket [", "string 'a'", "punctuation ,", "string 'b'", "bracket ]", "bracket )", "bracket ]",
                    "punctuation .", "name price", "punctuation .", "function avg", "bracket (", "bracket )",
                ])
        // Jayway names may hold `-` and start with a digit, and a path may start without `$`.
        #expect(
            Self.describe("store.my-key.2nd", .jayway) == [
                "name store", "punctuation .", "name my-key", "punctuation .", "name 2nd",
            ])
        // The same text, read with the RFC 9535 rules.
        #expect(
            Self.describe("$.my-key.avg()") == [
                "root $", "punctuation .", "name my", "plain -", "plain key", "punctuation .", "name avg", "bracket (",
                "bracket )",
            ])
    }

    @Test func rangesIndexTheGivenText() {
        let expression = "$['café 🐈‍⬛'][?@.n == 'é']"
        let tokens = JSONPath.tokens(in: expression)
        #expect(
            tokens.map { String(expression[$0.range]) } == [
                "$", "[", "'café 🐈‍⬛'", "]", "[", "?", "@", ".", "n", "==", "'é'", "]",
            ])
    }

    /// The lexer never decides validity: broken and half-typed text still gives runs, and never traps.
    @Test(arguments: [
        "", " ", "$", "$.", "$..", "$[", "$[?", "$['unclosed", "$[?@.a == 'x", "$[?(@.a =~ /abc", "]]))}}", "@@@",
        "$.a[?@.b ==]", "$[?=]", "&|=~", "$...", "-", "$[-]", "$[1e]", "\\", "$['\\", "{[(",
    ])
    func brokenInput(_ expression: String) {
        for dialect in JSONPath.Dialect.allCases {
            #expect(Self.coversEveryNonBlank(expression, dialect), "\(dialect): \(expression)")
        }
    }

    /// Every selector of the compliance test suite, valid or not, in both Dialects.
    @Test func complianceSelectors() {
        for test in ComplianceTestSuite.cases {
            for dialect in JSONPath.Dialect.allCases {
                #expect(Self.coversEveryNonBlank(test.selector, dialect), "\(test.name), \(dialect)")
            }
            if !test.invalid {
                #expect(JSONPath.tokens(in: test.selector).first?.kind == .root, "\(test.name)")
            }
        }
    }
}
