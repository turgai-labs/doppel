import Doppel

extension Evaluator {
    // MARK: Places

    func read(_ place: Place, in frame: Frame) async throws -> Value {
        switch place {
        case .local(let local):
            return frame.frame(local.depth).slots[local.slot]
        case .global(let name):
            return try await evaluate(Typed.global(name), in: frame)
        case .stored(nil, -1):
            return frame.selfFrame.selfValue ?? .void
        case .stored(nil, let index):
            return try field(index, of: frame.selfFrame.selfValue ?? .void)
        case .stored(let base?, let index):
            return try field(index, of: try await read(base, in: frame))
        case .subscripted(let base, let keys, let member):
            var arguments: [Value] = []
            for key in keys { arguments.append(try await evaluate(key, in: frame)) }
            return try await standard(member, on: try await read(base, in: frame), arguments, as: .dynamic)
        case .property(let base, let member):
            return try await standard(member, on: try await read(base, in: frame), [], as: .dynamic)
        case .optional(let base):
            guard case .optional(let wrapped?) = try await read(base, in: frame) else {
                throw Trap(message: "Unexpectedly found nil while unwrapping an Optional value")
            }
            return wrapped
        }
    }

    func write(_ place: Place, _ value: Value, in frame: Frame) async throws {
        switch place {
        case .local(let local):
            frame.frame(local.depth).slots[local.slot] = value
        case .global(let name):
            globalValues[name] = value
        case .stored(nil, -1):
            frame.selfFrame.selfValue = value
        case .stored(nil, let index):
            let owner = frame.selfFrame
            switch owner.selfValue {
            case .actor(let instance)?: instance.fields[index] = value
            case .structure(let name, var fields)?:
                fields[index] = value
                owner.selfValue = .structure(name, fields)
            default: throw Trap(message: "'self' has no properties")
            }
        case .stored(let base?, let index):
            guard case .structure(let name, var fields) = try await read(base, in: frame) else {
                throw Trap(message: "not a value with properties")
            }
            fields[index] = value
            try await write(base, .structure(name, fields), in: frame)
        case .subscripted(let base, let keys, let member):
            var arguments: [Value] = []
            for key in keys { arguments.append(try await evaluate(key, in: frame)) }
            var container = try await read(base, in: frame)
            try setSubscript(member, &container, arguments, to: value)
            try await write(base, container, in: frame)
        case .property(let base, let member):
            try await write(
                base, try settingProperty(member, of: try await read(base, in: frame), to: value), in: frame)
        case .optional(let base):
            try await write(base, .optional(value), in: frame)
        }
    }

    // MARK: Operators

    func binary(_ op: String, _ lhs: Value, _ rhs: Value) throws -> Value {
        switch (op, lhs, rhs) {
        case ("==", _, _): return .bool(try Self.equal(lhs, rhs))
        case ("!=", _, _): return .bool(!(try Self.equal(lhs, rhs)))
        case ("<", _, _): return .bool(try Self.compare(lhs, rhs) < 0)
        case (">", _, _): return .bool(try Self.compare(lhs, rhs) > 0)
        case ("<=", _, _): return .bool(try Self.compare(lhs, rhs) <= 0)
        case (">=", _, _): return .bool(try Self.compare(lhs, rhs) >= 0)
        case ("..<", .int(let lower), .int(let upper)):
            guard lower <= upper else { throw Trap(message: "Range requires lowerBound <= upperBound") }
            return .array((lower..<upper).map(Value.int))
        case (_, .date, _), (_, .decimal, _):
            guard let value = foundationBinary(op, lhs, rhs) else {
                throw Trap(message: "'\(op)' can't be applied to these values")
            }
            return value
        case ("...", .int(let lower), .int(let upper)):
            guard lower <= upper else { throw Trap(message: "Range requires lowerBound <= upperBound") }
            return .array((lower...upper).map(Value.int))
        case (_, .int, _), (_, .fixed, _):
            guard let a = Integer(lhs), let b = Integer(rhs) else {
                throw Trap(message: "'\(op)' can't be applied to these values")
            }
            return try integerBinary(op, a, b)
        case (_, .double(let a), .double(let b)):
            switch op {
            case "+": return .double(a + b)
            case "-": return .double(a - b)
            case "*": return .double(a * b)
            case "/": return .double(a / b)
            default: throw Trap(message: "'\(op)' can't be applied to two Doubles")
            }
        case ("+", .string(let a), .string(let b)): return .string(a + b)
        case ("+", .array(let a), .array(let b)): return .array(a + b)
        case ("+", .duration(let a), .duration(let b)): return .duration(a + b)
        default: throw Trap(message: "'\(op)' can't be applied to these values")
        }
    }

    static func equal(_ lhs: Value, _ rhs: Value) throws -> Bool {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.character(let a), .character(let b)): return a == b
        case (.fixed(let k, let a), .fixed(let l, let b)): return k == l && a == b
        case (.void, .void): return true
        case (.optional(nil), .optional(nil)): return true
        case (.optional(let a?), .optional(let b?)): return try equal(a, b)
        case (.optional, .optional): return false
        case (.optional(let a?), _): return try equal(a, rhs)
        case (_, .optional(let b?)): return try equal(lhs, b)
        case (.optional(nil), _), (_, .optional(nil)): return false
        case (.array(let a), .array(let b)): return try a.count == b.count && zip(a, b).allSatisfy { try equal($0, $1) }
        case (.set(let a), .set(let b)):
            return try a.count == b.count && a.allSatisfy { element in try b.contains { try equal($0, element) } }
        case (.tuple(let a), .tuple(let b)): return try a.count == b.count && zip(a, b).allSatisfy { try equal($0, $1) }
        case (.dictionary(let a), .dictionary(let b)):
            return try a.count == b.count
                && a.allSatisfy { pair in try b.contains { try equal($0.key, pair.key) && equal($0.value, pair.value) }
                }
        case (.structure(let a, let x), .structure(let b, let y)):
            return try a == b && zip(x, y).allSatisfy { try equal($0, $1) }
        case (.enumCase(let a, let c, let x), .enumCase(let b, let d, let y)):
            return try a == b && c == d && zip(x, y).allSatisfy { try equal($0, $1) }
        case (.object(let a), .object(let b)): return a == b
        case (.actor(let a), .actor(let b)): return a === b
        case (.duration(let a), .duration(let b)): return a == b
        default: return foundationEqual(lhs, rhs) ?? false
        }
    }

    static func compare(_ lhs: Value, _ rhs: Value) throws -> Int {
        switch (lhs, rhs) {
        case (.int(let a), .int(let b)): return a < b ? -1 : a > b ? 1 : 0
        case (.double(let a), .double(let b)): return a < b ? -1 : a > b ? 1 : 0
        case (.string(let a), .string(let b)): return a < b ? -1 : a > b ? 1 : 0
        case (.character(let a), .character(let b)): return a < b ? -1 : a > b ? 1 : 0
        case (.tuple(let a), .tuple(let b)):
            for (x, y) in zip(a, b) {
                let order = try compare(x, y)
                if order != 0 { return order }
            }
            return 0
        case (.structure("Unicode.Scalar", let a), .structure("Unicode.Scalar", let b)): return try compare(a[0], b[0])
        case (.fixed, .fixed):
            guard let a = Integer(lhs), let b = Integer(rhs) else {
                throw Trap(message: "these values can't be compared")
            }
            return compareIntegers(a, b)
        case (.duration(let a), .duration(let b)): return a < b ? -1 : a > b ? 1 : 0
        default:
            guard let order = foundationCompare(lhs, rhs) else { throw Trap(message: "these values can't be compared") }
            return order
        }
    }

    // MARK: Describing

    /// Whether the enum `type` is one of coding keys.
    func isCodingKey(_ type: String) -> Bool {
        program.type(named: type)?.conformances.contains("CodingKey") ?? false
    }

    /// A coding key's text and number, as Swift synthesizes them: its raw `String` value or else its
    /// case's name; its raw `Int` value, when it has one.
    func codingKey(_ type: String, _ caseName: String) -> (text: String, number: Int?) {
        let raw = rawValue(of: type, caseName)
        let text: String = if case .string(let written)? = raw { written } else { caseName }
        let number: Int? = if case .int(let written)? = raw { written } else { nil }
        return (text, number)
    }

    /// A coding key as Swift says it: `CodingKeys(stringValue: "name", intValue: nil)`.
    func codingKeyDescription(_ type: String, _ caseName: String) -> String {
        let key = codingKey(type, caseName)
        let shortName = type.split(separator: ".").last.map(String.init) ?? type
        return "\(shortName)(stringValue: \"\(key.text)\", intValue: \(key.number.map(String.init) ?? "nil"))"
    }

    /// A value as `String(describing:)` writes it, as an interpolation does: a struct with its
    /// properties' labels, an enum's case with its values'.
    func describe(_ value: Value) -> String {
        switch value {
        case .string(let text): text
        case .character(let character): String(character)
        case .structure("Unicode.Scalar", let fields): (try? Self.unicodeScalar(fields)).map { String($0) } ?? ""
        case .metatype(let type): type.printedName
        case .enumCase(let type, let caseName, let values) where values.isEmpty && isCodingKey(type):
            codingKeyDescription(type, caseName)
        default: debugDescribe(value, top: true)
        }
    }

    /// As Swift writes a value inside a collection: strings quoted.
    func debugDescribe(_ value: Value, top: Bool = false) -> String {
        switch value {
        case .int(let number): return "\(number)"
        case .double(let number): return "\(number)"
        case .bool(let flag): return "\(flag)"
        case .string(let text): return top ? text : "\"\(text)\""
        case .character(let character): return top ? String(character) : "\"\(character)\""
        case .structure("Unicode.Scalar", let fields):
            let text = (try? Self.unicodeScalar(fields)).map { String($0) } ?? ""
            return top ? text : "\"\(text)\""
        case .fixed: return Integer(value)?.description ?? "?"
        case .void: return "()"
        case .optional(nil): return "nil"
        case .optional(let wrapped?): return "Optional(\(debugDescribe(wrapped)))"
        case .array(let elements), .set(let elements):
            return "[\(elements.map { debugDescribe($0) }.joined(separator: ", "))]"
        case .dictionary(let pairs):
            return pairs.isEmpty
                ? "[:]"
                : "[\(pairs.map { "\(debugDescribe($0.key)): \(debugDescribe($0.value))" }.joined(separator: ", "))]"
        case .tuple(let elements): return "(\(elements.map { debugDescribe($0) }.joined(separator: ", ")))"
        case .structure(let name, let fields):
            let labels = program.type(named: name)?.storedNames ?? []
            let fields = zip(labels, fields).map { "\($0): \(debugDescribe($1))" }.joined(separator: ", ")
            // Inside a collection, or an optional, Swift writes a type with its module and the
            // types it's in; on its own, by its name alone.
            return top ? "\(Self.ownName(name))(\(fields))" : "\(module).\(name)(\(fields))"
        case .enumCase(let typeName, let name, let values) where values.isEmpty && isCodingKey(typeName):
            return codingKeyDescription(typeName, name)
        case .enumCase(let typeName, let name, let values):
            let qualified = top ? name : "\(module).\(typeName).\(name)"
            guard !values.isEmpty else { return qualified }
            let labels = program.type(named: typeName)?.caseValues(name).map(\.label) ?? []
            let written = values.enumerated().map { index, value in
                (index < labels.count ? labels[index] : nil).map { "\($0): \(debugDescribe(value))" }
                    ?? debugDescribe(value)
            }
            return "\(qualified)(\(written.joined(separator: ", ")))"
        case .actor(let instance): return instance.type
        case .object(let handle): return handle.reference
        case .function: return "(Function)"
        case .duration(let duration): return "\(duration)"
        case .task: return "Task"
        case .metatype(let type): return type.printedName
        case .stream: return "AsyncStream"
        case .continuation: return "AsyncStream.Continuation"
        case .streamIterator: return "AsyncStream.Iterator"
        case .date, .decimal, .uuid, .url, .data: return Self.foundationDescription(value) ?? ""
        }
    }

    static func typeName(of value: Value) -> String {
        switch value {
        case .structure(let name, _), .enumCase(let name, _, _): name
        case .actor(let instance): instance.type
        default: "\(value)"
        }
    }

    /// A type's name without the types it's in, as Swift describes it: `Inner` for `Outer.Inner`.
    static func ownName(_ name: String) -> String {
        name.split(separator: ".").last.map(String.init) ?? name
    }

    // MARK: Casts

    /// A value as another type at runtime: an object's answer as the type it's used as, an array
    /// as an array of what its elements convert to, an optional's value converted.
    func cast(_ value: Value, from source: SwiftType, to target: SwiftType, _ kind: Cast) async throws -> Value {
        let converted: Value?
        do {
            converted = try await runtimeValue(value, from: source, as: target)
        } catch {
            converted = nil
        }
        switch kind {
        case .check: return .bool(converted != nil)
        case .conditional: return .optional(converted)
        case .forced:
            guard let converted else { throw Trap(message: "Could not cast value of type '\(source)' to '\(target)'") }
            return converted
        }
    }

    private func runtimeValue(_ value: Value, from source: SwiftType, as target: SwiftType) async throws -> Value? {
        switch (source, target) {
        case (.dynamic, _), (.existential, _), (.unresolved, _):
            return try await self.value(try portable(value, as: .dynamic), as: target)
        case (.optional(let wrapped), .optional(let targetWrapped)):
            guard case .optional(let inner?) = value else { return .optional(nil) }
            return try await runtimeValue(inner, from: wrapped, as: targetWrapped).map { .optional($0) }
        case (_, .optional(let wrapped)):
            return try await runtimeValue(value, from: source, as: wrapped).map { .optional($0) }
        case (.array(let element), .array(let targetElement)):
            guard case .array(let elements) = value else { return nil }
            var made: [Value] = []
            for element_ in elements {
                guard let converted = try await runtimeValue(element_, from: element, as: targetElement) else {
                    return nil
                }
                made.append(converted)
            }
            return .array(made)
        case (_, .existential), (_, .dynamic):
            return value
        default:
            return source == target ? value : nil
        }
    }
}

extension Typed {
    static func global(_ name: String) -> Typed { Typed(.global(name), .dynamic) }
}
