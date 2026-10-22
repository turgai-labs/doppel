/// A type, as Swift has it: what every expression in a module is, decided once, before it runs.
public indirect enum SwiftType: Hashable, Sendable, CustomStringConvertible {
    case int
    case double
    case bool
    case string
    case character
    /// A fixed-width integer other than `Int`.
    case fixedInteger(FixedInteger)
    case void
    /// What a function that never returns returns: `fatalError()`.
    case never
    case optional(SwiftType)
    case array(SwiftType)
    case dictionary(key: SwiftType, value: SwiftType)
    /// A tuple's elements, each with its label, `nil` for none.
    case tuple([SwiftType], labels: [String?])
    case function(parameters: [SwiftType], result: SwiftType, effects: Effects)
    /// A struct, enum, actor or protocol the module declares, with its generic arguments.
    case named(String, arguments: [SwiftType])
    /// A value of any type that conforms to the protocols: `any Actor`, `any Sendable`; `Any` has none.
    case existential([String])
    /// A generic parameter, such as `T` in `map<T>` or `Element` in `Array`, until a use binds it;
    /// or an associated type of one, such as `S.Element`.
    case parameter(String)
    /// A function's parameter the function may change, which its caller sees: `inout T`.
    case `inout`(SwiftType)
    /// The answer to a message sent to an `Object` whose type isn't declared: whatever it is, read
    /// as the type it's used as, and checked when it comes. Swift can't type it; it's Doppel's.
    case dynamic
    /// What couldn't be decided, because of a problem already said: anything is taken of it, and
    /// nothing more is said, as Swift says a problem once.
    case unresolved

    public static func named(_ name: String) -> SwiftType { .named(name, arguments: []) }

    /// `Any`.
    public static let any = SwiftType.existential([])

    public var description: String {
        switch self {
        case .int: "Int"
        case .double: "Double"
        case .bool: "Bool"
        case .string: "String"
        case .character: "Character"
        case .fixedInteger(let kind): kind.rawValue
        case .void: "()"
        case .never: "Never"
        case .optional(let wrapped):
            switch wrapped {
            case .function, .existential: "(\(wrapped))?"
            default: "\(wrapped)?"
            }
        case .array(let element): "[\(element)]"
        case .dictionary(let key, let value): "[\(key) : \(value)]"
        case .tuple(let elements, let labels):
            "(\(zip(elements, labels).map { element, label in label.map { "\($0): \(element)" } ?? element.description }.joined(separator: ", ")))"
        case .function(let parameters, let result, let effects):
            "(\(parameters.map(\.description).joined(separator: ", ")))\(effects.written) -> \(result)"
        case .named(let name, let arguments):
            arguments.isEmpty ? name : "\(name)<\(arguments.map(\.description).joined(separator: ", "))>"
        case .existential(let protocols):
            protocols.isEmpty ? "Any" : "any " + protocols.joined(separator: " & ")
        case .parameter(let name): name
        case .inout(let wrapped): "inout \(wrapped)"
        case .dynamic: "Object's answer"
        case .unresolved: "<<error type>>"
        }
    }

    /// Whether it's one of Swift's integer types: `Int`, or a fixed-width one.
    public var isInteger: Bool {
        switch self {
        case .int, .fixedInteger: true
        default: false
        }
    }

    /// The type an optional wraps, or the type itself.
    public var unwrapped: SwiftType {
        if case .optional(let wrapped) = self { wrapped } else { self }
    }

    public var isOptional: Bool {
        if case .optional = self { true } else { false }
    }

    /// The name a type's members are declared under: `Array` for `[Int]`.
    var declarationName: String? {
        switch self {
        case .int: "Int"
        case .double: "Double"
        case .bool: "Bool"
        case .string: "String"
        case .character: "Character"
        case .fixedInteger(let kind): kind.rawValue
        case .optional: "Optional"
        case .array: "Array"
        case .dictionary: "Dictionary"
        case .named(let name, _): name
        default: nil
        }
    }

    /// The generic arguments a type's declaration is extended with: `["Element": Int]` for `[Int]`.
    var genericBindings: [String: SwiftType] {
        switch self {
        case .array(let element): ["Element": element]
        case .optional(let wrapped): ["Wrapped": wrapped]
        case .dictionary(let key, let value):
            ["Key": key, "Value": value, "Element": .tuple([key, value], labels: ["key", "value"])]
        default: [:]
        }
    }

    /// This type with each generic parameter as `bindings` has it.
    func substituting(_ bindings: [String: SwiftType]) -> SwiftType {
        guard !bindings.isEmpty else { return self }
        switch self {
        case .parameter(let name): return bindings[name] ?? self
        case .inout(let wrapped): return .inout(wrapped.substituting(bindings))
        case .optional(let wrapped): return .optional(wrapped.substituting(bindings))
        case .array(let element): return .array(element.substituting(bindings))
        case .dictionary(let key, let value):
            return .dictionary(key: key.substituting(bindings), value: value.substituting(bindings))
        case .tuple(let elements, let labels): return .tuple(elements.map { $0.substituting(bindings) }, labels: labels)
        case .function(let parameters, let result, let effects):
            return .function(
                parameters: parameters.map { $0.substituting(bindings) }, result: result.substituting(bindings),
                effects: effects)
        case .named(let name, let arguments):
            return .named(name, arguments: arguments.map { $0.substituting(bindings) })
        default: return self
        }
    }

    /// Whether a generic parameter is still in it, unbound.
    var isOpen: Bool {
        switch self {
        case .parameter: true
        case .optional(let wrapped), .inout(let wrapped): wrapped.isOpen
        case .array(let element): element.isOpen
        case .dictionary(let key, let value): key.isOpen || value.isOpen
        case .tuple(let elements, _): elements.contains(where: \.isOpen)
        case .function(let parameters, let result, _): parameters.contains(where: \.isOpen) || result.isOpen
        case .named(_, let arguments): arguments.contains(where: \.isOpen)
        default: false
        }
    }

    /// Whether a generic parameter other than `fixed` is still in it, unbound: those fixed are the
    /// types they stand for where it's used, as `Value` is inside `Holder<Value>`.
    func isOpen(besides fixed: Set<String>) -> Bool {
        switch self {
        case .parameter(let name): !fixed.contains(name)
        case .optional(let wrapped), .inout(let wrapped): wrapped.isOpen(besides: fixed)
        case .array(let element): element.isOpen(besides: fixed)
        case .dictionary(let key, let value): key.isOpen(besides: fixed) || value.isOpen(besides: fixed)
        case .tuple(let elements, _): elements.contains { $0.isOpen(besides: fixed) }
        case .function(let parameters, let result, _):
            parameters.contains { $0.isOpen(besides: fixed) } || result.isOpen(besides: fixed)
        case .named(_, let arguments): arguments.contains { $0.isOpen(besides: fixed) }
        default: false
        }
    }

    /// Binds the generic parameters in `self`, a declared type, so that it's `actual`, as Swift
    /// infers them: `[T]` and `[Inner]` bind `T` to `Inner`.
    func bind(to actual: SwiftType, into bindings: inout [String: SwiftType]) {
        switch (self, actual) {
        case (.parameter(let name), _):
            if bindings[name] == nil, !actual.isOpen { bindings[name] = actual }
        case (.optional(let declared), .optional(let actual)), (.inout(let declared), .inout(let actual)):
            declared.bind(to: actual, into: &bindings)
        case (.optional(let declared), _): declared.bind(to: actual, into: &bindings)
        case (.array(let declared), .array(let actual)): declared.bind(to: actual, into: &bindings)
        case (.dictionary(let key, let value), .dictionary(let actualKey, let actualValue)):
            key.bind(to: actualKey, into: &bindings)
            value.bind(to: actualValue, into: &bindings)
        case (.tuple(let declared, _), .tuple(let actual, _)) where declared.count == actual.count:
            for (declared, actual) in zip(declared, actual) { declared.bind(to: actual, into: &bindings) }
        case (.function(let parameters, let result, _), .function(let actualParameters, let actualResult, _))
        where parameters.count == actualParameters.count:
            for (declared, actual) in zip(parameters, actualParameters) { declared.bind(to: actual, into: &bindings) }
            result.bind(to: actualResult, into: &bindings)
        case (.named(let name, let declared), .named(let actualName, let actual))
        where name == actualName && declared.count == actual.count:
            for (declared, actual) in zip(declared, actual) { declared.bind(to: actual, into: &bindings) }
        default: break
        }
    }
}

/// Swift's fixed-width integer types other than `Int`, each its own type, as in Swift.
public enum FixedInteger: String, Hashable, Sendable, CaseIterable {
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case int64 = "Int64"
    case uint = "UInt"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case uint32 = "UInt32"
    case uint64 = "UInt64"

    public var isSigned: Bool {
        switch self {
        case .int8, .int16, .int32, .int64: true
        case .uint, .uint8, .uint16, .uint32, .uint64: false
        }
    }

    public var bitWidth: Int {
        switch self {
        case .int8, .uint8: 8
        case .int16, .uint16: 16
        case .int32, .uint32: 32
        case .int64, .uint, .uint64: 64
        }
    }
}

/// What a function may do besides return: wait, and throw.
public struct Effects: Hashable, Sendable {
    public var async: Bool
    public var throwing: Bool

    public init(async: Bool = false, throwing: Bool = false) {
        self.async = async
        self.throwing = throwing
    }

    public static let none = Effects()

    var written: String {
        switch (async, throwing) {
        case (false, false): ""
        case (true, false): " async"
        case (false, true): " throws"
        case (true, true): " async throws"
        }
    }
}
