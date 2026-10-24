import Doppel

/// Values as they cross to the host and back, as `Codable` writes them: a struct as an object of
/// its stored properties, an enum without values as its case's name or raw value, one with values
/// as `{"case": {"label": value}}`, `nil` as null.
extension Evaluator {
    func portable(_ value: Value, as type: SwiftType) throws -> Portable {
        switch (value, type) {
        case (.int(let number), _): return .int(number)
        case (.double(let number), _): return .double(number)
        case (.bool(let flag), _): return .bool(flag)
        case (.string(let text), _): return .string(text)
        case (.character(let character), _): return .string(String(character))
        case (.fixed, _):
            // As `Codable` writes it, a number; one past `Int`'s range only as a `Double` holds it.
            guard let integer = Integer(value) else { return .null }
            return Self.portableInteger(integer.value)
        case (.void, _): return .null
        case (.optional(nil), _): return .null
        case (.optional(let wrapped?), _): return try portable(wrapped, as: type.unwrapped)
        case (.array(let elements), .array(let element)):
            return .array(try elements.map { try portable($0, as: element) })
        case (.set(let elements), .named("Set", let arguments)) where arguments.count == 1:
            return .array(try elements.map { try portable($0, as: arguments[0]) })
        case (.set(let elements), _): return .array(try elements.map { try portable($0, as: .dynamic) })
        case (.array(let elements), _): return .array(try elements.map { try portable($0, as: .dynamic) })
        case (.dictionary(let pairs), .dictionary(let key, let valueType)) where key == .string:
            return .object(
                try pairs.map { pair in
                    guard case .string(let name) = pair.key else {
                        throw Trap(message: "a dictionary's key isn't a string")
                    }
                    return (name, try portable(pair.value, as: valueType))
                })
        case (.dictionary(let pairs), .dictionary(let key, let valueType)) where key == .int:
            // `Codable` writes a dictionary keyed by `Int` as an object, each key as its digits.
            return .object(
                try pairs.map { pair in
                    guard case .int(let number) = pair.key else {
                        throw Trap(message: "a dictionary's key isn't an Int")
                    }
                    return (String(number), try portable(pair.value, as: valueType))
                })
        case (.dictionary(let pairs), .dictionary(let key, let valueType)):
            // `Codable` writes a dictionary whose keys aren't strings as its keys and values in turn.
            return .array(try pairs.flatMap { [try portable($0.key, as: key), try portable($0.value, as: valueType)] })
        case (.dictionary(let pairs), _):
            return .object(
                try pairs.map { pair in
                    guard case .string(let name) = pair.key else {
                        throw Trap(message: "a dictionary's key isn't a string")
                    }
                    return (name, try portable(pair.value, as: .dynamic))
                })
        case (.tuple(let elements), .tuple(let types, _)):
            return .array(try zip(elements, types).map { try portable($0, as: $1) })
        case (.tuple(let elements), _): return .array(try elements.map { try portable($0, as: .dynamic) })
        case (.structure(let name, let fields), _):
            guard let declaration = program.type(named: name) else { throw Trap(message: "no type '\(name)'") }
            // As synthesized `Codable` writes it: an optional that's `nil` is left out.
            return .object(
                try zip(declaration.storedNames, fields).enumerated().compactMap { index, pair in
                    if case .optional(nil) = pair.1 { return nil }
                    return (pair.0, try portable(pair.1, as: fieldType(declaration, index)))
                })
        case (.enumCase(let name, let caseName, let values), _):
            guard let declaration = program.type(named: name) else { throw Trap(message: "no type '\(name)'") }
            if values.isEmpty {
                if let raw = rawValue(of: name, caseName) { return try portable(raw, as: .dynamic) }
                return .string(caseName)
            }
            let parameters = declaration.caseValues(caseName)
            return .object([
                (
                    caseName,
                    .object(
                        try zip(parameters, values).enumerated().compactMap { index, pair in
                            if case .optional(nil) = pair.1 { return nil }
                            return (pair.0.label ?? "_\(index)", try portable(pair.1, as: pair.0.type))
                        })
                )
            ])
        case (.date, _), (.decimal, _), (.uuid, _), (.url, _): return Self.foundationPortable(value) ?? .null
        case (.actor, _): return .reference(host.itself)
        case (.object(let handle), _): return .reference(handle)
        case (.duration(let duration), _):
            let (seconds, attoseconds) = duration.components
            return .double(Double(seconds) + Double(attoseconds) / 1e18)
        case (.function, _), (.task, _), (.metatype, _), (.stream, _), (.continuation, _), (.streamIterator, _):
            throw Trap(message: "a function can't be sent to another object")
        }
    }

    /// A portable value read as `type`, as `Codable` reads it. What isn't of its type is refused
    /// with where in the value it is, from `path`, as `DecodingError` gives its coding path.
    func value(_ portable: Portable, as type: SwiftType, at path: ValuePath = ValuePath()) throws -> Value {
        switch (portable, type) {
        case (_, .unresolved), (_, .dynamic), (_, .existential), (_, .any): return shaped(portable)
        case (.null, .optional): return .optional(nil)
        case (_, .optional(let wrapped)): return .optional(try value(portable, as: wrapped, at: path))
        case (.int(let number), .int): return .int(number)
        case (.double(let number), .int) where number.rounded() == number: return .int(Int(number))
        case (.int(let number), .double): return .double(Double(number))
        case (.double(let number), .double): return .double(number)
        case (.bool(let flag), .bool): return .bool(flag)
        case (.string(let text), .string): return .string(text)
        case (.string(let text), .character) where text.count == 1: return .character(text.first!)
        case (.int(let number), .fixedInteger(let kind)):
            guard case .optional(let exact?) = try? integer(Integer(.int(number))!, as: kind, "init(exactly:)") else {
                throw path.mismatch("\(number) isn't \(Self.a(kind.rawValue))")
            }
            return exact
        case (.null, .void), (_, .void): return .void
        case (.array(let elements), .array(let element)):
            return .array(try elements.enumerated().map { try value($1, as: element, at: path.appending(.index($0))) })
        case (.array(let elements), .named("Set", let arguments)) where arguments.count == 1:
            return .set(
                try Self.unique(
                    try elements.enumerated().map { try value($1, as: arguments[0], at: path.appending(.index($0))) }))
        case (.object(let members), .dictionary(.string, let valueType)):
            return .dictionary(
                try members.map {
                    (key: .string($0.0), value: try value($0.1, as: valueType, at: path.appending(.key($0.0))))
                })
        case (.object(let members), .dictionary(.int, let valueType)):
            return .dictionary(
                try members.map { name, member in
                    guard let number = Int(name) else {
                        throw path.appending(.key(name)).mismatch("\"\(name)\" isn't an 'Int' key")
                    }
                    return (key: .int(number), value: try value(member, as: valueType, at: path.appending(.key(name))))
                })
        case (.array(let elements), .dictionary(let key, let valueType)) where elements.count % 2 == 0:
            // Keys and values in turn, as `Codable` writes a dictionary whose keys aren't strings.
            return .dictionary(
                try stride(from: 0, to: elements.count, by: 2).map { index in
                    (
                        key: try value(elements[index], as: key, at: path.appending(.index(index))),
                        value: try value(elements[index + 1], as: valueType, at: path.appending(.index(index + 1)))
                    )
                })
        case (.array(let elements), .tuple(let types, _)) where elements.count == types.count:
            return .tuple(
                try zip(elements, types).enumerated().map {
                    try value($1.0, as: $1.1, at: path.appending(.member("\($0)")))
                })
        // An object is only an actor's, and of the type wanted when it says what it is: another
        // type is never one. One that doesn't say is checked when it's called.
        case (.reference(let handle), .named(let name, _)) where program.type(named: name)?.kind == .actor:
            if let given = handle.type, given != name {
                throw path.mismatch("\(Self.a(given)) isn't \(Self.a(name))")
            }
            return .object(handle)
        case (_, .named(let name, _)) where Self.foundationTypes.contains(name):
            do {
                return try Self.foundationValue(portable, as: name) ?? shaped(portable)
            } catch let trap as Trap {
                throw path.mismatch(trap.message)
            }
        case (_, .named(let name, _)):
            guard let declaration = program.type(named: name) else { throw Trap(message: "no type '\(name)'") }
            if declaration.isStruct || declaration.kind == .standard {
                guard case .object = portable else { throw path.mismatch("\(portable) isn't \(Self.a(name))") }
                return .structure(
                    name,
                    try declaration.storedNames.enumerated().map { index, field in
                        let fieldType = fieldType(declaration, index)
                        guard let member = portable[field] else {
                            if case .optional = fieldType { return .optional(nil) }
                            throw path.mismatch("\(Self.a(name)) needs '\(field)'")
                        }
                        return try value(member, as: fieldType, at: path.appending(.member(field)))
                    })
            }
            if declaration.isEnum {
                if case .string(let text) = portable {
                    if let caseName = declaration.caseNames.first(where: {
                        rawValue(of: name, $0).map(Self.text) == text || $0 == text
                    }) {
                        return .enumCase(name, caseName, [])
                    }
                }
                if case .int(let number) = portable,
                    let caseName = declaration.caseNames.first(where: {
                        if case .int(number)? = rawValue(of: name, $0) { true } else { false }
                    })
                {
                    return .enumCase(name, caseName, [])
                }
                if case .object(let members) = portable, members.count == 1, let (caseName, payload) = members.first,
                    declaration.caseNames.contains(caseName)
                {
                    let parameters = declaration.caseValues(caseName)
                    return .enumCase(
                        name, caseName,
                        try parameters.enumerated().map { index, parameter in
                            let key = parameter.label ?? "_\(index)"
                            guard let member = payload[key] else {
                                if case .optional = parameter.type { return .optional(nil) }
                                throw path.mismatch("'\(name).\(caseName)' needs '\(key)'")
                            }
                            return try value(
                                member, as: parameter.type,
                                at: path.appending(.member(caseName)).appending(.member(key)))
                        })
                }
                throw path.mismatch("\(portable) isn't a case of '\(name)'")
            }
            throw path.mismatch("\(portable) isn't \(Self.a(name))")
        default:
            throw path.mismatch("\(portable) isn't \(Self.a("\(type)"))")
        }
    }

    /// A type's name with its article, as said: "a 'Date'", "an 'Int'".
    static func a(_ name: String) -> String {
        ("AEIOU".contains(name.first ?? " ") ? "an" : "a") + " '\(name)'"
    }

    /// A portable value as it is, by its shape, for a value whose type isn't declared.
    func shaped(_ portable: Portable) -> Value {
        switch portable {
        case .null: .optional(nil)
        case .bool(let flag): .bool(flag)
        case .int(let number): .int(number)
        case .double(let number): .double(number)
        case .string(let text): .string(text)
        case .array(let elements): .array(elements.map(shaped))
        case .object(let members): .dictionary(members.map { (key: .string($0.0), value: shaped($0.1)) })
        case .reference(let handle): .object(handle)
        }
    }

    private static func portableInteger(_ value: some FixedWidthInteger) -> Portable {
        Int(exactly: value).map(Portable.int) ?? .double(Double(value))
    }

    static func text(_ value: Value) -> String? {
        if case .string(let text) = value { return text }
        return nil
    }
}
