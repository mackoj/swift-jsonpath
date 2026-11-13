/// A dictionary that remembers the order in which keys were inserted.
///
/// Arazzo documents are frequently authored by hand, and the order of map entries
/// (outputs, components, JSON Schema properties, ...) carries meaning for readers.
/// `OrderedDictionary` preserves that order through decoding and encoding whenever
/// the underlying decoder exposes keys in document order (YAML via Yams does).
///
/// Equality and hashing are **order-insensitive**, matching JSON object semantics.
public struct OrderedDictionary<Key: Hashable, Value> {
    public private(set) var keys: [Key]
    /// The values, in the order of ``keys``.
    public private(set) var values: [Value]
    /// The position of each key in ``keys`` and ``values``, once there are more than ``linearSearchLimit``; empty
    /// before that, when a linear search costs no more than hashing the key and saves an allocation per object.
    /// Iterating reads the two arrays and never hashes.
    private var positions: [Key: Int]
    static var linearSearchLimit: Int { 8 }

    public init() {
        keys = []
        values = []
        positions = [:]
    }

    /// Creates an ordered dictionary from a sequence of pairs. Later duplicates win
    /// but keep the position of the first occurrence.
    public init<S: Sequence>(_ elements: S) where S.Element == (Key, Value) {
        self.init()
        for (key, value) in elements { self[key] = value }
    }

    public var count: Int { keys.count }

    private func position(of key: Key) -> Int? {
        keys.count > Self.linearSearchLimit ? positions[key] : keys.firstIndex(of: key)
    }
    public var isEmpty: Bool { keys.isEmpty }

    public subscript(key: Key) -> Value? {
        get { position(of: key).map { values[$0] } }
        set {
            if let newValue {
                if let position = position(of: key) {
                    values[position] = newValue
                } else {
                    keys.append(key)
                    values.append(newValue)
                    if keys.count == Self.linearSearchLimit + 1 {
                        positions = Dictionary(uniqueKeysWithValues: zip(keys, keys.indices))
                    } else if keys.count > Self.linearSearchLimit + 1 {
                        positions[key] = keys.count - 1
                    }
                }
            } else {
                removeValue(forKey: key)
            }
        }
    }

    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        guard let position = position(of: key) else { return nil }
        keys.remove(at: position)
        if keys.count > Self.linearSearchLimit {
            positions[key] = nil
            for later in keys[position...] { positions[later]! -= 1 }
        } else {
            positions = [:]
        }
        return values.remove(at: position)
    }

    public func contains(key: Key) -> Bool { position(of: key) != nil }

    /// Calls `body` with the value for `key` in place, so a uniquely referenced value is not copied, or returns `nil`
    /// when there is no such key.
    mutating func modifyValue<R>(forKey key: Key, _ body: (inout Value) throws -> R) rethrows -> R? {
        guard let position = position(of: key) else { return nil }
        return try body(&values[position])
    }

    /// The stored key equal to `key` and its value. (Swift `String` equality is canonical-equivalence
    /// based; callers that need code-point equality compare the returned key.)
    func entry(forKey key: Key) -> (key: Key, value: Value)? {
        guard let position = position(of: key) else { return nil }
        return (keys[position], values[position])
    }

    public func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> OrderedDictionary<Key, T> {
        var result = OrderedDictionary<Key, T>()
        for (key, value) in self { result[key] = try transform(value) }
        return result
    }

    public func compactMapValues<T>(_ transform: (Value) throws -> T?) rethrows -> OrderedDictionary<Key, T> {
        var result = OrderedDictionary<Key, T>()
        for (key, value) in self {
            if let value = try transform(value) { result[key] = value }
        }
        return result
    }

    public func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> OrderedDictionary {
        var result = OrderedDictionary()
        for element in self where try isIncluded(element) { result[element.key] = element.value }
        return result
    }

    /// An unordered view of the contents.
    public var dictionary: [Key: Value] { Dictionary(uniqueKeysWithValues: zip(keys, values)) }
}

extension OrderedDictionary: RandomAccessCollection {
    public typealias Element = (key: Key, value: Value)
    public typealias Index = Int

    public var startIndex: Int { 0 }
    public var endIndex: Int { keys.count }

    public subscript(position: Int) -> Element {
        (keys[position], values[position])
    }
}

extension OrderedDictionary: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (Key, Value)...) {
        self.init(elements)
    }
}

extension OrderedDictionary: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy { rhs[$0.key] == $0.value }
    }
}

extension OrderedDictionary: Hashable where Value: Hashable {
    /// Order-insensitive, like `Dictionary`'s: the members' hashes are combined with XOR, which ignores order.
    public func hash(into hasher: inout Hasher) {
        var members = 0
        for (key, value) in self {
            var member = Hasher()
            member.combine(key)
            member.combine(value)
            members ^= member.finalize()
        }
        hasher.combine(count)
        hasher.combine(members)
    }
}

extension OrderedDictionary: Sendable where Key: Sendable, Value: Sendable {}

extension OrderedDictionary: CustomStringConvertible {
    public var description: String {
        "[" + map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "]"
    }
}

extension OrderedDictionary: Decodable where Key == String, Value: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: JSONCodingKey.self)
        self.init()
        for key in container.allKeys {
            self[key.stringValue] = try container.decode(Value.self, forKey: key)
        }
    }
}

extension OrderedDictionary: Encodable where Key == String, Value: Encodable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: JSONCodingKey.self)
        for (key, value) in self {
            try container.encode(value, forKey: JSONCodingKey(key))
        }
    }
}
