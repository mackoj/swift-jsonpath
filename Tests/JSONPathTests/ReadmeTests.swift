import JSONPath
import Testing

/// Keeps the README snippets compiling and truthful.
@Suite("README examples")
struct ReadmeTests {
    static let document = try! JSONValue(
        parsing: """
            {"store": {"book": [
              {"category": "reference", "author": "Nigel Rees", "title": "Sayings of the Century", "price": 8.95},
              {"category": "fiction", "author": "Herman Melville", "title": "Moby Dick", "isbn": "0-553-21311-3", "price": 8.99},
              {"category": "fiction", "author": "J. R. R. Tolkien", "title": "The Lord of the Rings", "price": 22.99}
            ], "bicycle": {"color": "red", "price": 19.95}}}
            """)

    @Test func usage() throws {
        let document = Self.document
        let cheap = try JSONPath("$.store.book[?@.price < 10].title")
        #expect(try cheap.values(in: document) == ["Sayings of the Century", "Moby Dick"])
        #expect(
            try cheap.paths(in: document).map(\.description) == [
                "$['store']['book'][0]['title']", "$['store']['book'][1]['title']",
            ])
        #expect(try cheap.nodes(in: document).count == 2)
        #expect(try document.query("$..price") == [.number(8.95), .number(8.99), .number(22.99), .number(19.95)])
        #expect(
            try JSONPath("$.store.book[?match(@.author, '.*Tolkien')].title").values(in: document) == [
                "The Lord of the Rings"
            ])
        #expect(try JSONPath("$.store.book[?count(@.isbn) > 0].title").values(in: document) == ["Moby Dick"])
    }

    @Test func jayway() throws {
        let document = Self.document
        let fiction = try JSONPath("store.book[?(@.category == 'fiction' && @.price > 10)].title", dialect: .jayway)
        #expect(try fiction.values(in: document) == ["The Lord of the Rings"])
        let pattern = try JSONPath("$..book[?(@.author =~ /.*REES/i)].price", dialect: .jayway)
        #expect(try pattern.values(in: document) == [.number(8.95)])
        let count = try JSONPath("$.store.book.length()", dialect: .jayway)
        #expect(try count.values(in: document) == [3])
        let inList = try JSONPath("$.store.book[?(@.category in ['fiction'])]", dialect: .jayway)
        #expect(try inList.values(in: document).count == 2)
    }

    @Test func jsonPointer() throws {
        let document = Self.document
        let title = try JSONPointer("/store/book/0/title")
        #expect(title.resolve(in: document) == "Sayings of the Century")
        #expect(title.tokens == ["store", "book", "0", "title"])
        #expect(try JSONPointer("#/store/bicycle").resolve(in: document)?["color"] == "red")
        #expect(try JSONPointer("/a~1b/m~0n").tokens == ["a/b", "m~n"])
        #expect(JSONPointer(tokens: ["a/b", "m~n"]).description == "/a~1b/m~0n")
        #expect(try JSONPointer("/store/missing").resolve(in: document) == nil)
        #expect(
            try JSONPath("$..price").paths(in: document).map(\.jsonPointer.description) == [
                "/store/book/0/price", "/store/book/1/price", "/store/book/2/price", "/store/bicycle/price",
            ])
        var copy = document
        try copy.set("red", at: JSONPointer("/store/bicycle/color"))
        try copy.set(["title": "Dune", "price": 9.99], at: JSONPointer("/store/book/-"))
        #expect(copy["store"]?["book"]?[3] == ["title": "Dune", "price": 9.99])
        #expect(throws: JSONPointer.ParseError.self) { try JSONPointer("store") }
    }

    @Test func mutations() throws {
        var copy = Self.document
        try copy.replace(JSONPath("$..price"), with: 0)
        try copy.remove(JSONPath("$.store.bicycle"))
        try copy.map(JSONPath("$..title")) { .string($0.stringValue!.uppercased()) }
        try copy.set("new", at: JSONPointer("/store/book/0/tag"))
        try copy.set(1, at: NormalizedPath(["store", "book", 0, "price"]))
        #expect(
            copy["store"]?["book"]?[0] == [
                "category": "reference", "author": "Nigel Rees", "title": "SAYINGS OF THE CENTURY", "price": 1,
                "tag": "new",
            ])
        #expect(copy["store"]?["bicycle"] == nil)
    }

    @Test func codable() throws {
        struct Book: Codable, Equatable {
            let title: String
            let price: Double
        }
        let books = try JSONValueDecoder().decode(
            Book.self, from: JSONPath("$.store.book[*]").values(in: Self.document))
        #expect(books.first == Book(title: "Sayings of the Century", price: 8.95))
        let value = try JSONValue(encoding: books)
        #expect(value[0]?.objectValue?.keys == ["title", "price"])
        #expect(value.jsonString(prettyPrinted: true).hasPrefix("[\n  {\n    \"title\": "))
    }

    @Test func validation() {
        #expect(JSONPath.validate("$.store[?@.price <]") != nil)
        #expect(JSONPath.validate("$.store.book[0]") == nil)
        do {
            _ = try JSONPath("$.a[", dialect: .rfc9535)
            Issue.record("expected a parse error")
        } catch let error as JSONPath.ParseError {
            #expect(error.position == 4)
        } catch {
            Issue.record("\(error)")
        }
    }

    @Test func syntaxColouring() {
        let query = "$[?@.price < 10].title"
        let tokens = JSONPath.tokens(in: query)
        #expect(
            tokens.map { String(query[$0.range]) } == ["$", "[", "?", "@", ".", "price", "<", "10", "]", ".", "title"])
        #expect(tokens.prefix(4).map(\.kind) == [.root, .bracket, .punctuation, .current])
    }
}
