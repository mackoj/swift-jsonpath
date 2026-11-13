import Benchmark
import Foundation
import JSONPath

/// The documents the benchmarks read: the compliance test suite the tests run, and a generated store far larger than
/// the README's, to show costs that grow with size.
enum Fixtures {
    /// `Tests/JSONPathTests/Fixtures/cts.json`, 232 KB of real-world JSON: long strings, deep nesting, escapes.
    static let ctsText: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Tests/JSONPathTests/Fixtures/cts.json")
        return try! String(contentsOf: url, encoding: .utf8)
    }()

    static let cts: JSONValue = try! JSONValue(parsing: ctsText)

    /// The README's bookstore with `books` books, each with nested reviews: about 1.4 MB of JSON for 5,000 books.
    static func storeText(books: Int = 5_000) -> String {
        let categories = ["reference", "fiction", "poetry", "history"]
        let items = (0..<books).map { index in
            """
            {"category": "\(categories[index % categories.count])", "author": "Author \(index % 97)", \
            "title": "Title \(index) \\u00e9\\n", "isbn": "0-\(index)-21311-3", "price": \(Double(index % 40) + 0.99), \
            "available": \(index % 3 != 0), "reviews": [{"stars": \(index % 5 + 1), "by": "r\(index)"}, \
            {"stars": \((index + 2) % 5 + 1), "by": "s\(index)", "tags": ["a", "b", null]}]}
            """
        }
        return """
            {"store": {"book": [\(items.joined(separator: ","))], \
            "bicycle": {"color": "red", "price": 399.99}}, "expensive": 10}
            """
    }

    static let largeText = storeText()
    static let large: JSONValue = try! JSONValue(parsing: largeText)
}

/// Expressions in both Dialects, from simple to every kind of segment and selector.
let rfcExpressions = [
    "$.store.book[0].title", "$['store']['book'][*]['author']", "$..author", "$.store.book[-1:0:-2]",
    "$..book[?@.price < 10 && @.category == 'fiction'].title", "$..book[?match(@.isbn, '0-1.*')]",
    "$.store.book[?count(@.reviews[?@.stars > 3]) > 1]", "$..*",
]
let jaywayExpressions = [
    "$.store.book[0].title", "$['store']['book'][*]['author']", "$..author", "$.store.book[-2:]",
    "$..book[?(@.price < 10 && @.category == 'fiction')].title", "$..book[?(@.isbn =~ /0-1.*/)]",
    "$.store.book[?(@.reviews.length() > 1)]", "$..book.length()",
]

/// A Codable model of one book.
struct Book: Codable {
    struct Review: Codable {
        var stars: Int
        var by: String
        var tags: [String?]?
    }
    var category: String
    var author: String
    var title: String
    var isbn: String
    var price: Double
    var available: Bool
    var reviews: [Review]
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident, .retainCount],
        // Exact counts and microseconds, so a change of a few percent shows up in a comparison.
        timeUnits: .microseconds,
        units: [.mallocCountTotal: .count, .retainCount: .count],
        maxDuration: .seconds(2),
        maxIterations: 1_000
    )

    // MARK: JSON text

    Benchmark("Parse JSON, compliance suite") { _ in
        blackHole(try JSONValue(parsing: Fixtures.ctsText))
    }
    Benchmark("Parse JSON, large") { _ in
        blackHole(try JSONValue(parsing: Fixtures.largeText))
    }
    Benchmark("Parse JSON from bytes, large") { benchmark in
        let bytes = Array(Fixtures.largeText.utf8)
        benchmark.startMeasurement()
        blackHole(try JSONValue(parsing: bytes))
    }
    Benchmark("Print JSON, large") { _ in
        blackHole(Fixtures.large.jsonString)
    }
    Benchmark("Print JSON pretty and sorted, large") { _ in
        blackHole(Fixtures.large.jsonString(prettyPrinted: true, sortedKeys: true))
    }

    // MARK: Parsing paths

    Benchmark("Parse paths, RFC 9535") { _ in
        for expression in rfcExpressions { blackHole(try JSONPath(expression)) }
    }
    Benchmark("Parse paths, Jayway") { _ in
        for expression in jaywayExpressions { blackHole(try JSONPath(expression, dialect: .jayway)) }
    }

    // MARK: Queries

    for (dialect, expressions) in [(JSONPath.Dialect.rfc9535, rfcExpressions), (.jayway, jaywayExpressions)] {
        let name = dialect == .rfc9535 ? "RFC 9535" : "Jayway"
        let paths = expressions.map { try! JSONPath($0, dialect: dialect) }
        Benchmark("Query \(name), every expression, large") { _ in
            for path in paths { blackHole(try path.values(in: Fixtures.large)) }
        }
        Benchmark("Query \(name), descendants, large") { _ in
            blackHole(try paths[2].values(in: Fixtures.large))
        }
        Benchmark("Query \(name), filter, large") { _ in
            blackHole(try paths[4].values(in: Fixtures.large))
        }
        Benchmark("Query \(name), nodes with normalized paths, large") { _ in
            blackHole(try paths[1].nodes(in: Fixtures.large))
        }
    }
    let everything = try! JSONPath("$..*")
    Benchmark("Query RFC 9535, every node, compliance suite") { _ in
        blackHole(try everything.values(in: Fixtures.cts))
    }

    // MARK: Pointers and mutation

    let pointers = (0..<1_000).map { try! JSONPointer("/store/book/\($0 * 5)/reviews/1/by") }
    Benchmark("Resolve JSON pointers, large") { _ in
        for pointer in pointers { blackHole(pointer.resolve(in: Fixtures.large)) }
    }
    let prices = try! JSONPath("$..price")
    Benchmark("Replace every price, large") { benchmark in
        var document = Fixtures.large
        benchmark.startMeasurement()
        blackHole(try document.replace(prices, with: 1))
        blackHole(document)
    }
    let unavailable = try! JSONPath("$.store.book[?@.available == false]")
    Benchmark("Remove filtered books, large") { benchmark in
        var document = Fixtures.large
        benchmark.startMeasurement()
        blackHole(try document.remove(unavailable))
        blackHole(document)
    }

    // MARK: Codable

    let books = try! JSONPath("$.store.book[*]").values(in: Fixtures.large)
    Benchmark("Decode books, large") { _ in
        blackHole(try JSONValueDecoder().decode(Book.self, from: books))
    }
    let decoded = try! JSONValueDecoder().decode(Book.self, from: books)
    Benchmark("Encode books, large") { _ in
        blackHole(try JSONValueEncoder().encode(decoded))
    }
}
