extension JSONValue {
    /// Errors raised by mutations.
    public struct MutationError: Error, Hashable, Sendable, CustomStringConvertible {
        public let message: String
        public var description: String { message }
    }

    // MARK: - JSONPath driven

    /// Replaces every node selected by `path` with `value`. Returns the number of replaced nodes.
    @discardableResult
    public mutating func replace(_ path: JSONPath, with value: JSONValue) throws -> Int {
        try map(path) { _ in value }
    }

    /// Removes every node selected by `path`. Returns the number of removed nodes.
    /// Removing the root leaves `null`.
    @discardableResult
    public mutating func remove(_ path: JSONPath) throws -> Int {
        try map(path) { _ in nil }
    }

    /// Transforms every node selected by `path`; returning `nil` removes the node.
    ///
    /// - Note: `JSONValue` is `ExpressibleByNilLiteral`, so in `condition ? value : nil` Swift infers
    ///   `nil` as `JSONValue.null` (which *sets* null). Use `return nil` from an `if` to remove.
    /// Returns the number of visited nodes. Nodes computed by functions (which have no location) are ignored.
    @discardableResult
    public mutating func map(_ path: JSONPath, _ transform: (JSONValue) throws -> JSONValue?) throws -> Int {
        var seen = Set<NormalizedPath>()
        let locations = try path.nodes(in: self).compactMap(\.location).filter { seen.insert($0).inserted }
        // Apply deepest / last-index first so earlier locations stay valid while removing.
        for location in locations.sorted(by: >) {
            guard let current = self[location] else { continue }
            if let replacement = try transform(current) {
                try set(replacement, at: location)
            } else {
                remove(at: location)
            }
        }
        return locations.count
    }

    /// Calls `body` for every value selected by `path`.
    public func forEach(_ path: JSONPath, _ body: (JSONValue) throws -> Void) throws {
        for node in try path.nodes(in: self) { try body(node.value) }
    }

    // MARK: - Location driven

    /// Sets the value at an existing location (object member or array element).
    /// Setting a missing object member adds it.
    public mutating func set(_ value: JSONValue, at path: NormalizedPath) throws {
        try Self.update(&self, path.elements[...]) { target in
            target = value
        }
    }

    /// Removes the value at a location. Does nothing if it does not exist.
    public mutating func remove(at path: NormalizedPath) {
        guard let last = path.elements.last, let parent = path.parent else {
            self = .null
            return
        }
        try? Self.update(&self, parent.elements[...]) { container in
            // The container is moved out before it changes, as in `update`, so removing does not copy it.
            switch last {
            case .name(let name):
                guard case .object(var object)? = container else { return }
                container = nil
                object.removeValue(forKey: name)
                container = .object(object)
            case .index(let index):
                guard case .array(var array)? = container, array.indices.contains(index) else { return }
                container = nil
                array.remove(at: index)
                container = .array(array)
            }
        }
    }

    /// Sets a value at a JSON Pointer (RFC 6901). Missing object members are created; for arrays,
    /// an index equal to the count or `-` appends.
    public mutating func set(_ value: JSONValue, at pointer: JSONPointer) throws {
        guard !pointer.tokens.isEmpty else {
            self = value
            return
        }
        var elements: [NormalizedPath.Element] = []
        var current: JSONValue? = self
        for (offset, token) in pointer.tokens.enumerated() {
            let isLast = offset == pointer.tokens.count - 1
            switch current {
            case .array(let array)?:
                if token == "-" {
                    guard isLast else { throw MutationError(message: "'-' can only be the last token of \(pointer)") }
                    elements.append(.index(array.count))
                } else if let index = JSONPointer.arrayIndex(token), index <= array.count {
                    guard isLast || index < array.count else {
                        throw MutationError(message: "Index \(token) is out of bounds in \(pointer)")
                    }
                    elements.append(.index(index))
                    current = index < array.count ? array[index] : nil
                } else {
                    throw MutationError(message: "'\(token)' is not a valid array index in \(pointer)")
                }
            case .object(let object)?:
                elements.append(.name(token))
                current = object[token]
                if current == nil && !isLast {
                    throw MutationError(message: "'\(token)' does not exist in \(pointer)")
                }
            default:
                throw MutationError(message: "Cannot descend into a scalar at '\(token)' in \(pointer)")
            }
        }
        try Self.update(&self, elements[...]) { target in target = value }
    }

    static func update(
        _ value: inout JSONValue, _ elements: ArraySlice<NormalizedPath.Element>, _ body: (inout JSONValue?) -> Void
    ) throws {
        guard let first = elements.first else {
            var optional: JSONValue? = value
            value = .null  // so `body` gets the only reference and changes it in place
            body(&optional)
            value = optional ?? .null
            return
        }
        let rest = elements.dropFirst()
        // Each container is moved out of `value` before it changes, and put back after, even on a throw: while
        // `value` still held it, the container would be shared and every change would copy it whole. The switch is
        // on `first` alone, since a tuple of `(value, first)` would hold a second reference too.
        switch first {
        case .name(let name):
            guard case .object(var object) = value else { throw cannotApply(first, to: value) }
            value = .null
            defer { value = .object(object) }
            if rest.isEmpty {
                var child = object[name]
                // Keeps the member's position and drops the second reference.
                if case .some = child { object[name] = .null }
                body(&child)
                object[name] = child
            } else {
                let found = try object.modifyValue(forKey: name) { child in try update(&child, rest, body) }
                guard found != nil else { throw MutationError(message: "No member '\(name)'") }
            }
        case .index(let index):
            guard case .array(var array) = value else { throw cannotApply(first, to: value) }
            value = .null
            defer { value = .array(array) }
            if rest.isEmpty {
                // `.none`, not `nil`: in this ternary Swift reads `nil` as `JSONValue.null`.
                var child: JSONValue? = array.indices.contains(index) ? .some(array[index]) : .none
                if case .some = child { array[index] = .null }  // drops the second reference
                body(&child)
                if let child {
                    if array.indices.contains(index) {
                        array[index] = child
                    } else if index == array.count {
                        array.append(child)
                    } else {
                        throw MutationError(message: "Index \(index) is out of bounds")
                    }
                } else if array.indices.contains(index) {
                    array.remove(at: index)
                }
            } else {
                guard array.indices.contains(index) else {
                    throw MutationError(message: "Index \(index) is out of bounds")
                }
                try update(&array[index], rest, body)
            }
        }
    }

    static func cannotApply(_ element: NormalizedPath.Element, to value: JSONValue) -> MutationError {
        MutationError(message: "Cannot apply \(element) to a \(value.typeName)")
    }

    /// The JSON type name: `object`, `array`, `string`, `number`, `boolean` or `null`.
    public var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .integer, .number: "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }
}
