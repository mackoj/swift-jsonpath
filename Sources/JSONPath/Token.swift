extension JSONPath {
    /// One run of a JSONPath expression's text, for syntax colouring.
    ///
    /// Tokens come from ``JSONPath/tokens(in:dialect:)``, a lexer that only colours: it never decides whether the
    /// expression is valid. Use ``JSONPath/init(_:dialect:)`` and ``ParseError/position`` for that.
    public struct Token: Hashable, Sendable {
        /// What a run of text is.
        public enum Kind: Hashable, Sendable, CaseIterable {
            /// The root identifier `$`.
            case root
            /// The current node identifier `@`.
            case current
            /// A member name: after `.` or `..`, or quoted in a bracketed selection (`['name']`, quotes included).
            case name
            /// The wildcard selector `*`.
            case wildcard
            /// A string literal in a filter or a function argument, quotes included.
            case string
            /// A number: an index, a slice bound or a literal.
            case number
            /// `true`, `false` or `null`.
            case keyword
            /// A comparison or logical operator: `==`, `<=`, `&&`, `!`, and in the Jayway Dialect `=~`, `in`,
            /// `nin`, `size`, `empty`, … as well.
            case `operator`
            /// A function name: a filter function such as `length` in `length(@.tags)`, or a Jayway path function
            /// such as `avg` in `$.prices.avg()`. The parentheses are ``bracket`` tokens.
            case function
            /// `[`, `]`, `(`, `)`, `{` or `}`.
            case bracket
            /// `.`, `..`, `,`, `:` or the filter selector `?`.
            case punctuation
            /// A Jayway regular expression literal, `/pattern/flags`.
            case regex
            /// Text the lexer does not recognise. It is not an error: errors come from compiling the expression.
            case plain
        }

        public let kind: Kind
        /// The run's range in the text passed to ``JSONPath/tokens(in:dialect:)``.
        public let range: Range<String.Index>

        public init(kind: Kind, range: Range<String.Index>) {
            self.kind = kind
            self.range = range
        }
    }

    /// The tokens of `expression`, in order, for syntax colouring.
    ///
    /// The runs do not overlap. Blanks between them belong to no token; every other character belongs to exactly
    /// one. The lexer follows the `dialect`'s lexical rules (Jayway member names may contain `-` and start with a
    /// digit, Jayway has regular expressions and word operators, …) but never rejects text: what it does not
    /// recognise is a ``Token/Kind/plain`` token. It never throws and accepts any string, including an expression
    /// that is being typed.
    ///
    /// ```swift
    /// let query = "$[?@.price < 10].title"
    /// let tokens = JSONPath.tokens(in: query)
    /// tokens.map { query[$0.range] }  // ["$", "[", "?", "@", ".", "price", "<", "10", "]", ".", "title"]
    /// ```
    public static func tokens(in expression: String, dialect: Dialect = .rfc9535) -> [Token] {
        var lexer = Lexer(text: expression, dialect: dialect)
        lexer.run()
        return lexer.tokens
    }
}

/// The colouring lexer behind ``JSONPath/tokens(in:dialect:)``. It mirrors the lexical rules of `RFC9535Parser` and
/// `JaywayParser` and keeps a stack of open brackets to tell a selection's names from a filter's strings.
private struct Lexer {
    typealias Kind = JSONPath.Token.Kind

    enum Frame: Equatable {
        /// `[` after a path: a bracketed selection.
        case selection
        /// A selection that met `?`.
        case filter
        /// `(`: a group or a function's arguments.
        case group
        /// A Jayway JSON literal, `[` or `{` where a value is expected.
        case literal
    }

    let text: String
    let scalars: String.UnicodeScalarView
    let dialect: JSONPath.Dialect
    var index: String.Index
    var tokens: [JSONPath.Token] = []
    var frames: [Frame] = []

    init(text: String, dialect: JSONPath.Dialect) {
        self.text = text
        self.scalars = text.unicodeScalars
        self.dialect = dialect
        self.index = text.startIndex
    }

    static let rfcOperators = ["==", "!=", "<=", ">=", "&&", "||", "<", ">", "!"]
    static let jaywayOperators = ["===", "!==", "==", "!=", "<=", ">=", "=~", "&&", "||", "<", ">", "!"]

    var current: Unicode.Scalar? { index < scalars.endIndex ? scalars[index] : nil }

    func peek() -> Unicode.Scalar? {
        guard index < scalars.endIndex else { return nil }
        let next = scalars.index(after: index)
        return next < scalars.endIndex ? scalars[next] : nil
    }

    mutating func advance() { index = scalars.index(after: index) }

    mutating func emit(_ kind: Kind, from start: String.Index) {
        tokens.append(JSONPath.Token(kind: kind, range: start..<index))
    }

    /// `true` where a value is expected: inside a filter, a group or a JSON literal.
    var expectsValue: Bool { frames.last.map { $0 != .selection } ?? false }
    var inFilter: Bool { frames.contains { $0 != .selection } }

    /// `true` when the previous token ends a path, so a `[` that follows opens a selection.
    var followsPath: Bool {
        guard let last = tokens.last else { return false }
        switch last.kind {
        case .root, .current, .name, .wildcard: return true
        case .punctuation: return scalars[last.range.lowerBound] == "."
        case .bracket: return scalars[last.range.lowerBound] == "]"
        default: return false
        }
    }

    static func isBlank(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" }
    static func isDigit(_ c: Unicode.Scalar?) -> Bool { c.map { $0 >= "0" && $0 <= "9" } ?? false }
    static func isRFCNameFirst(_ c: Unicode.Scalar) -> Bool {
        (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || c == "_" || c.value >= 0x80
    }
    static func isWordScalar(_ c: Unicode.Scalar) -> Bool {
        c.properties.isAlphabetic || c == "_" || isDigit(c)
    }

    /// `JaywayParser.isNameTerminator`.
    func isJaywayNameTerminator(_ c: Unicode.Scalar) -> Bool {
        switch c {
        case ".", "[", "(", " ", "\t", "\n", "\r": return true
        default: break
        }
        guard inFilter else { return c == ")" || c == "]" || c == "," }
        return "()]=!<>&|,~'\"".unicodeScalars.contains(c)
    }

    mutating func run() {
        while let c = current {
            let start = index
            if Self.isBlank(c) {
                advance()
                continue
            }
            switch c {
            case "$":
                advance()
                emit(.root, from: start)
            case "@":
                advance()
                emit(.current, from: start)
            case ".":
                advance()
                if current == "." { advance() }
                emit(.punctuation, from: start)
                member()
            case "*":
                advance()
                emit(.wildcard, from: start)
            case "[":
                frames.append(!expectsValue || followsPath ? .selection : .literal)
                advance()
                emit(.bracket, from: start)
            case "{":
                frames.append(.literal)
                advance()
                emit(.bracket, from: start)
            case "(":
                frames.append(.group)
                advance()
                emit(.bracket, from: start)
            case "]", ")", "}":
                if !frames.isEmpty { frames.removeLast() }
                advance()
                emit(.bracket, from: start)
            case "?":
                if frames.last == .selection { frames[frames.count - 1] = .filter }
                advance()
                emit(.punctuation, from: start)
            case ",", ":":
                advance()
                emit(.punctuation, from: start)
            case "'", "\"":
                let kind: Kind = frames.last == .selection ? .name : .string
                string()
                emit(kind, from: start)
            case "/" where dialect == .jayway && expectsValue:
                regex()
                emit(.regex, from: start)
            default:
                other(c, from: start)
            }
        }
    }

    mutating func other(_ c: Unicode.Scalar, from start: String.Index) {
        if dialect == .jayway, frames.isEmpty, !isJaywayNameTerminator(c) {
            // A Jayway path may start without `$`, and a name may follow a bracket directly: `$..[*]foo`.
            jaywayName()
            emit(current == "(" ? .function : .name, from: start)
            return
        }
        if Self.isDigit(c) || (c == "-" && Self.isDigit(peek())) {
            number()
            emit(.number, from: start)
            return
        }
        let operators = dialect == .jayway ? Self.jaywayOperators : Self.rfcOperators
        if let symbol = operators.first(where: { hasPrefix($0) }) {
            for _ in symbol.unicodeScalars { advance() }
            emit(.operator, from: start)
            return
        }
        if Self.isWordScalar(c) {
            while let d = current, Self.isWordScalar(d) { advance() }
            let word = String(text[start..<index])
            if current == "(" {
                emit(.function, from: start)
            } else if word == "true" || word == "false" || word == "null" {
                emit(.keyword, from: start)
            } else if dialect == .jayway, expectsValue,
                JSONPath.ComparisonOperator.wordOperators[word.uppercased()] != nil
            {
                emit(.operator, from: start)
            } else {
                emit(.plain, from: start)
            }
            return
        }
        advance()
        emit(.plain, from: start)
    }

    func hasPrefix(_ symbol: String) -> Bool {
        var i = index
        for s in symbol.unicodeScalars {
            guard i < scalars.endIndex, scalars[i] == s else { return false }
            i = scalars.index(after: i)
        }
        return true
    }

    /// What follows `.` or `..`: a wildcard, a member name, or a Jayway path function's name.
    mutating func member() {
        let start = index
        guard let c = current else { return }
        if c == "*" {
            advance()
            emit(.wildcard, from: start)
            return
        }
        switch dialect {
        case .rfc9535:
            guard Self.isRFCNameFirst(c) else { return }
            while let d = current, Self.isRFCNameFirst(d) || Self.isDigit(d) { advance() }
            emit(.name, from: start)
        case .jayway:
            jaywayName()
            guard index > start else { return }
            emit(current == "(" ? .function : .name, from: start)
        }
    }

    mutating func jaywayName() {
        while let d = current, !isJaywayNameTerminator(d) { advance() }
    }

    /// A quoted string, to its closing quote or the end of the text.
    mutating func string() {
        let quote = current
        advance()
        while let c = current {
            advance()
            if c == quote { return }
            if c == "\\", current != nil { advance() }
        }
    }

    /// `/pattern/flags`, to the end of the text when it is not closed.
    mutating func regex() {
        advance()
        while let c = current {
            advance()
            if c == "/" {
                while let f = current, f.properties.isAlphabetic { advance() }
                return
            }
            if c == "\\", current != nil { advance() }
        }
    }

    /// `-? digits (. digits)? ([eE] [+-]? digits)?`
    mutating func number() {
        if current == "-" { advance() }
        while Self.isDigit(current) { advance() }
        if current == ".", Self.isDigit(peek()) {
            advance()
            while Self.isDigit(current) { advance() }
        }
        if current == "e" || current == "E" {
            let save = index
            advance()
            if current == "+" || current == "-" { advance() }
            guard Self.isDigit(current) else {
                index = save
                return
            }
            while Self.isDigit(current) { advance() }
        }
    }
}
