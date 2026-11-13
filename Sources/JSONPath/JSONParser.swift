extension JSONValue {
    /// An error raised while parsing JSON text.
    public struct ParseError: Error, Hashable, Sendable, CustomStringConvertible {
        public let message: String
        /// The byte offset in the UTF-8 input where the error was detected.
        public let offset: Int
        public var description: String { "Invalid JSON at offset \(offset): \(message)" }
    }

    /// Parses JSON text (RFC 8259), preserving the order of object members.
    ///
    /// Integers that fit in `Int` become ``integer(_:)``; other numbers become ``number(_:)``.
    /// When an object repeats a member name, the last value wins (at the first position).
    public init(parsing text: String) throws {
        var copy = text
        self = try copy.withUTF8 { buffer in
            var parser = JSONTextParser(buffer)
            return try parser.parseDocument()
        }
    }

    /// Parses UTF-8 encoded JSON text.
    public init(parsing bytes: some Collection<UInt8>) throws {
        let array = Array(bytes)
        self = try array.withUnsafeBufferPointer { buffer in
            var parser = JSONTextParser(buffer)
            return try parser.parseDocument()
        }
    }
}

struct JSONTextParser {
    let bytes: UnsafeBufferPointer<UInt8>
    var index = 0
    var depth = 0
    static let maximumDepth = 512

    init(_ bytes: UnsafeBufferPointer<UInt8>) {
        self.bytes = bytes
    }

    func fail(_ message: String) -> JSONValue.ParseError {
        JSONValue.ParseError(message: message, offset: index)
    }

    mutating func parseDocument() throws -> JSONValue {
        // Skip a UTF-8 byte order mark.
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { index = 3 }
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw fail("unexpected trailing characters") }
        return value
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    mutating func parseValue() throws -> JSONValue {
        guard index < bytes.count else { throw fail("unexpected end of input") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
        default: throw fail("unexpected character")
        }
    }

    mutating func expectLiteral(_ literal: StaticString) throws {
        let count = literal.utf8CodeUnitCount
        guard index + count <= bytes.count else { throw fail("invalid literal") }
        for offset in 0..<count where bytes[index + offset] != literal.utf8Start[offset] {
            throw fail("invalid literal")
        }
        index += count
    }

    mutating func parseObject() throws -> JSONValue {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else { throw fail("nesting too deep") }
        index += 1
        var object = OrderedDictionary<String, JSONValue>()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(object)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("expected a member name") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("expected ':'") }
            index += 1
            skipWhitespace()
            object[key] = try parseValue()
            skipWhitespace()
            guard index < bytes.count else { throw fail("unterminated object") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(object)
            }
            throw fail("expected ',' or '}'")
        }
    }

    mutating func parseArray() throws -> JSONValue {
        depth += 1
        defer { depth -= 1 }
        guard depth <= Self.maximumDepth else { throw fail("nesting too deep") }
        index += 1
        var array: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(array)
        }
        while true {
            skipWhitespace()
            array.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw fail("unterminated array") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            if bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(array)
            }
            throw fail("expected ',' or ']'")
        }
    }

    mutating func parseNumber() throws -> JSONValue {
        let start = index
        var isInteger = true
        if bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid number") }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
            if index < bytes.count, isDigit(bytes[index]) { throw fail("leading zeros are not allowed") }
        } else {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            isInteger = false
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid fraction") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            isInteger = false
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                index += 1
            }
            guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid exponent") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if isInteger, let int = integer(start..<index) { return .integer(int) }
        let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
        guard let double = Double(text) else { throw fail("invalid number") }
        return .number(double)
    }

    /// The integer in `range`, an optional `-` and digits, or `nil` when it does not fit in `Int`. Read from the
    /// bytes, without making a `String` first; a negative number is built downward so `Int.min` fits.
    func integer(_ range: Range<Int>) -> Int? {
        let negative = bytes[range.lowerBound] == UInt8(ascii: "-")
        var value = 0
        for index in (negative ? range.lowerBound + 1 : range.lowerBound)..<range.upperBound {
            let digit = Int(bytes[index] &- UInt8(ascii: "0"))
            let (shifted, overflowed) = value.multipliedReportingOverflow(by: 10)
            let (next, overflowedAgain) =
                negative ? shifted.subtractingReportingOverflow(digit) : shifted.addingReportingOverflow(digit)
            if overflowed || overflowedAgain { return nil }
            value = next
        }
        return value
    }

    func isDigit(_ byte: UInt8) -> Bool { byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") }

    /// A string without escapes is decoded once from its bytes. With escapes, the unescaped UTF-8 is gathered in
    /// a buffer and decoded once, rather than appended scalar by scalar.
    mutating func parseString() throws -> String {
        index += 1  // opening quote
        var hasEscapes = false
        var unescaped: [UInt8] = []
        var runStart = index
        func flushRun(_ end: Int) {
            unescaped.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[runStart..<end]))
        }
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                defer { index += 1 }
                guard hasEscapes else {
                    return String(decoding: UnsafeBufferPointer(rebasing: bytes[runStart..<index]), as: UTF8.self)
                }
                flushRun(index)
                return String(decoding: unescaped, as: UTF8.self)
            }
            if byte < 0x20 { throw fail("unescaped control character in string") }
            if byte == UInt8(ascii: "\\") {
                hasEscapes = true
                flushRun(index)
                index += 1
                guard index < bytes.count else { throw fail("unterminated escape") }
                let escaped = bytes[index]
                index += 1
                switch escaped {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): unescaped.append(escaped)
                case UInt8(ascii: "b"): unescaped.append(0x08)
                case UInt8(ascii: "f"): unescaped.append(0x0C)
                case UInt8(ascii: "n"): unescaped.append(0x0A)
                case UInt8(ascii: "r"): unescaped.append(0x0D)
                case UInt8(ascii: "t"): unescaped.append(0x09)
                case UInt8(ascii: "u"):
                    let high = try parseHex4()
                    if (0xD800...0xDBFF).contains(high) {
                        guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
                            bytes[index + 1] == UInt8(ascii: "u")
                        else { throw fail("unpaired surrogate") }
                        index += 2
                        let low = try parseHex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw fail("invalid low surrogate") }
                        let value = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                        unescaped.append(contentsOf: UTF8.encode(Unicode.Scalar(value)!)!)
                    } else if (0xDC00...0xDFFF).contains(high) {
                        throw fail("unpaired surrogate")
                    } else {
                        unescaped.append(contentsOf: UTF8.encode(Unicode.Scalar(high)!)!)
                    }
                default:
                    throw fail("invalid escape sequence")
                }
                runStart = index
                continue
            }
            index += 1
        }
        throw fail("unterminated string")
    }

    mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw fail("invalid unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw fail("invalid unicode escape")
            }
            value = value * 16 + digit
            index += 1
        }
        return value
    }
}
