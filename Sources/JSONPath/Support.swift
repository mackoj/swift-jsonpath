/// A coding key that can represent any string or integer key.
struct JSONCodingKey: CodingKey, Hashable, Sendable {
    var stringValue: String
    var intValue: Int?

    init(_ string: String) {
        stringValue = string
        intValue = nil
    }

    init(stringValue: String) { self.init(stringValue) }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}

extension String {
    func replacingAll(_ target: Character, with replacement: String) -> String {
        var result = ""
        for character in self {
            if character == target { result += replacement } else { result.append(character) }
        }
        return result
    }
}

/// The regular expressions compiled while one query runs. A filter calls `match`, `search` or `=~` once per node,
/// nearly always with the same pattern, and compiling a pattern costs far more than matching it. One cache lives as
/// long as one evaluation, so nothing is shared between queries or threads.
final class RegexCache {
    private var compiled: [String: Regex<AnyRegexOutput>?] = [:]

    /// The regex for `key`, compiled by `compile` the first time; a pattern that does not compile is remembered too.
    func regex(_ key: String, compile: () -> Regex<AnyRegexOutput>?) -> Regex<AnyRegexOutput>? {
        if let regex = compiled[key] { return regex }
        let regex = compile()
        compiled[key] = .some(regex)
        return regex
    }
}
