public import Doppel

// Integers as Swift's own types run them: each operation is done by the type the value is of, on
// its bits, so what overflows traps and what wraps wraps, as in Swift.

extension FixedInteger {
    /// The Swift type it is.
    var integerType: any FixedWidthInteger.Type {
        switch self {
        case .int8: Int8.self
        case .int16: Int16.self
        case .int32: Int32.self
        case .int64: Int64.self
        case .uint: UInt.self
        case .uint8: UInt8.self
        case .uint16: UInt16.self
        case .uint32: UInt32.self
        case .uint64: UInt64.self
        }
    }
}

/// The Swift type values of `kind` are: `Int` without one.
func integerType(of kind: FixedInteger?) -> any FixedWidthInteger.Type {
    guard let kind else { return Int.self }
    return kind.integerType
}

/// An integer value of either kind, as its Swift type: `Int`, or a fixed-width one, with the kind
/// it's to be written back as.
struct Integer {
    let kind: FixedInteger?
    let value: any FixedWidthInteger

    init?(_ value: Value) {
        switch value {
        case .int(let number): (kind, self.value) = (nil, number)
        case .fixed(let kind, let bits): (self.kind, self.value) = (kind, Self.decoded(kind.integerType, bits))
        default: return nil
        }
    }

    private static func decoded<T: FixedWidthInteger>(_ type: T.Type, _ bits: UInt64) -> any FixedWidthInteger {
        T(truncatingIfNeeded: bits)
    }

    /// `number` as a value of `kind`: `Int` without one.
    static func made<T: FixedWidthInteger>(_ number: T, as kind: FixedInteger?) -> Value {
        guard let kind else { return .int(Int(truncatingIfNeeded: number)) }
        return .fixed(kind, UInt64(truncatingIfNeeded: number))
    }

    var description: String { "\(value)" }
}

extension Evaluator {
    /// Two integers of one type, with an operator; or a shift, by any integer.
    func integerBinary(_ op: String, _ lhs: Integer, _ rhs: Integer) throws -> Value {
        if op == "<<" || op == ">>" {
            guard let amount = Self.exactInt(rhs.value) else {
                throw Trap(message: "Not enough bits to represent the passed value")
            }
            return Self.shiftedInteger(op, lhs.value, by: amount, kind: lhs.kind)
        }
        return try Self.combinedIntegers(op, lhs.value, rhs.value, kind: lhs.kind)
    }

    private static func exactInt(_ value: some FixedWidthInteger) -> Int? { Int(exactly: value) }

    private static func shiftedInteger<T: FixedWidthInteger>(
        _ op: String, _ value: T, by amount: Int, kind: FixedInteger?
    ) -> Value {
        Integer.made(op == "<<" ? value << amount : value >> amount, as: kind)
    }

    private static func combinedIntegers<T: FixedWidthInteger>(
        _ op: String, _ a: T, _ other: any FixedWidthInteger, kind: FixedInteger?
    ) throws -> Value {
        guard let b = other as? T else {
            throw Trap(message: "'\(op)' can't be applied to a \(T.self) and a \(type(of: other))")
        }
        func checked(_ result: (partialValue: T, overflow: Bool)) throws -> T {
            guard !result.overflow else { throw Trap(message: "Arithmetic overflow") }
            return result.partialValue
        }
        let result: T
        switch op {
        case "+": result = try checked(a.addingReportingOverflow(b))
        case "-": result = try checked(a.subtractingReportingOverflow(b))
        case "*": result = try checked(a.multipliedReportingOverflow(by: b))
        case "/":
            guard b != 0 else { throw Trap(message: "Division by zero") }
            result = try checked(a.dividedReportingOverflow(by: b))
        case "%":
            guard b != 0 else { throw Trap(message: "Division by zero in remainder operation") }
            result = try checked(a.remainderReportingOverflow(dividingBy: b))
        case "&+": result = a &+ b
        case "&-": result = a &- b
        case "&*": result = a &* b
        case "&": result = a & b
        case "|": result = a | b
        case "^": result = a ^ b
        default: throw Trap(message: "'\(op)' can't be applied to two \(T.self)s")
        }
        return Integer.made(result, as: kind)
    }

    /// `-x` and `~x`.
    func integerUnary(_ op: String, _ operand: Integer) throws -> Value {
        try Self.unaryInteger(op, operand.value, kind: operand.kind)
    }

    private static func unaryInteger<T: FixedWidthInteger>(_ op: String, _ value: T, kind: FixedInteger?) throws
        -> Value
    {
        switch op {
        case "~": return Integer.made(~value, as: kind)
        case "-":
            let (result, overflow) = T.zero.subtractingReportingOverflow(value)
            guard !overflow else { throw Trap(message: "Arithmetic overflow") }
            return Integer.made(result, as: kind)
        default: throw Trap(message: "'\(op)' can't be applied to a \(T.self)")
        }
    }

    static func compareIntegers(_ lhs: Integer, _ rhs: Integer) -> Int {
        Self.orderedFirst(lhs.value, rhs.value)
    }

    private static func orderedFirst<T: FixedWidthInteger>(_ a: T, _ b: any FixedWidthInteger) -> Int {
        Self.orderedSecond(b, after: a)
    }

    private static func orderedSecond<U: FixedWidthInteger>(_ b: U, after a: some FixedWidthInteger) -> Int {
        a < b ? -1 : a > b ? 1 : 0
    }

    /// An integer as another integer type, as `init(_:)`, `init(truncatingIfNeeded:)` and
    /// `init(exactly:)` make it: the first traps where the value doesn't fit, as Swift's does.
    func integer(_ source: Integer, as kind: FixedInteger?, _ how: String) throws -> Value {
        try Self.convertedSource(source.value, to: integerType(of: kind), kind: kind, how)
    }

    private static func convertedSource<S: FixedWidthInteger>(
        _ source: S, to type: any FixedWidthInteger.Type, kind: FixedInteger?, _ how: String
    ) throws -> Value {
        try Self.convertedTarget(type, from: source, kind: kind, how)
    }

    private static func convertedTarget<T: FixedWidthInteger>(
        _ type: T.Type, from source: some FixedWidthInteger, kind: FixedInteger?, _ how: String
    ) throws -> Value {
        switch how {
        case "init(truncatingIfNeeded:)": return Integer.made(T(truncatingIfNeeded: source), as: kind)
        case "init(exactly:)": return .optional(T(exactly: source).map { Integer.made($0, as: kind) })
        default:
            guard let exact = T(exactly: source) else {
                throw Trap(
                    message: source < 0 && !T.isSigned
                        ? "Negative value is not representable" : "Not enough bits to represent the passed value")
            }
            return Integer.made(exact, as: kind)
        }
    }

    /// A `Double` as an integer, as `init(_:)` makes it: its whole part, trapping where that
    /// doesn't fit.
    func integer(_ number: Double, as kind: FixedInteger?) throws -> Value {
        try Self.truncatedDouble(number, to: integerType(of: kind), kind: kind)
    }

    private static func truncatedDouble<T: FixedWidthInteger>(_ number: Double, to type: T.Type, kind: FixedInteger?)
        throws -> Value
    {
        guard number.isFinite else {
            throw Trap(message: "Double value cannot be converted to \(T.self) because it is either infinite or NaN")
        }
        guard let exact = T(exactly: number.rounded(.towardZero)) else {
            throw Trap(
                message:
                    "Double value cannot be converted to \(T.self) because the result would be greater than \(T.self).max or less than \(T.self).min"
            )
        }
        return Integer.made(exact, as: kind)
    }

    /// Text as an integer of a type, as `init?(_:)` reads it.
    static func integer(_ text: String, as kind: FixedInteger) -> Value {
        Self.parsedText(text, kind.integerType, kind: kind)
    }

    private static func parsedText<T: FixedWidthInteger>(_ text: String, _ type: T.Type, kind: FixedInteger) -> Value {
        .optional(T(text).map { Integer.made($0, as: kind) })
    }

    /// A type's `max`, `min` and `bitWidth`.
    static func integerStatic(_ name: String, of kind: FixedInteger?) -> Value? {
        Self.staticValue(name, integerType(of: kind), kind: kind)
    }

    private static func staticValue<T: FixedWidthInteger>(_ name: String, _ type: T.Type, kind: FixedInteger?) -> Value?
    {
        switch name {
        case "max": Integer.made(T.max, as: kind)
        case "min": Integer.made(T.min, as: kind)
        case "bitWidth": .int(T.bitWidth)
        default: nil
        }
    }

    /// An integer written in a radix, as `String(_:radix:uppercase:)` writes it.
    static func written(_ integer: Integer, radix: Int, uppercase: Bool) throws -> String {
        guard (2...36).contains(radix) else { throw Trap(message: "Radix must be between 2 and 36") }
        return Self.radixed(integer.value, radix: radix, uppercase: uppercase)
    }

    private static func radixed(_ value: some FixedWidthInteger, radix: Int, uppercase: Bool) -> String {
        String(value, radix: radix, uppercase: uppercase)
    }

    static func double(_ integer: Integer) -> Double {
        Self.doubled(integer.value)
    }

    private static func doubled(_ value: some FixedWidthInteger) -> Double { Double(value) }

    static func isMultiple(_ value: Integer, of other: Integer) throws -> Bool {
        try Self.multipleOf(value.value, of: other.value)
    }

    private static func multipleOf<T: FixedWidthInteger>(_ value: T, of other: any FixedWidthInteger) throws -> Bool {
        guard let other = other as? T else { throw Trap(message: "not the same integer type") }
        return value.isMultiple(of: other)
    }
}
