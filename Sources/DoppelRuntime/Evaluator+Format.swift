import Doppel

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// `String(format:)`, as Foundation writes it: each conversion of `format` as C's `printf` writes
/// it, and `%@` as the value's description.
extension Evaluator {
    func formatted(_ format: String, _ values: [Value]) throws -> String {
        var result = ""
        var remaining = values[...]
        var characters = format[...]
        while let percent = characters.firstIndex(of: "%") {
            result += characters[..<percent]
            characters = characters[characters.index(after: percent)...]
            // Its flags, width, precision and length, up to the letter that says what it writes.
            guard
                let end = characters.firstIndex(where: {
                    ($0.isLetter && !"hlqLjzt".contains($0)) || $0 == "@" || $0 == "%"
                })
            else { throw Trap(message: "the format ends in the middle of a conversion") }
            let conversion = characters[end]
            let spec = String(characters[..<end]).filter { !"hlqLjzt".contains($0) }
            characters = characters[characters.index(after: end)...]
            if conversion == "%" {
                result += "%"
                continue
            }
            guard let value = remaining.popFirst() else {
                throw Trap(message: "the format asks for more arguments than it's given")
            }
            result += try Self.converted(value, spec: spec, conversion: conversion, describe: describe)
        }
        return result + characters
    }

    /// One conversion: `%` and `spec`'s flags, width and precision, then `conversion`, of `value`.
    private static func converted(
        _ value: Value, spec: String, conversion: Character, describe: (Value) -> String
    ) throws -> String {
        switch conversion {
        case "@":
            let text = describe(value)
            // A width pads what it writes, as `%@` does.
            guard let width = Int(spec.filter(\.isNumber)), text.count < width else { return text }
            let padding = String(repeating: " ", count: width - text.count)
            return spec.hasPrefix("-") ? text + padding : padding + text
        case "d", "i":
            return try c("%\(spec)lld", integer(value))
        case "u", "x", "X", "o":
            return try c("%\(spec)ll\(conversion)", UInt64(bitPattern: integer(value)))
        case "f", "F", "e", "E", "g", "G", "a", "A":
            guard let number = number(value) else { throw Trap(message: "%\(conversion) takes a number") }
            return c("%\(spec)\(conversion)", number)
        default:
            throw Trap(message: "%\(conversion) isn't written by Doppel; use %@ for text")
        }
    }

    private static func integer(_ value: Value) throws -> Int64 {
        switch value {
        case .int(let number): return Int64(number)
        case .fixed(_, let bits): return Int64(bitPattern: bits)
        case .bool(let flag): return flag ? 1 : 0
        default: throw Trap(message: "an integer conversion takes an integer")
        }
    }

    private static func number(_ value: Value) -> Double? {
        switch value {
        case .double(let number): number
        case .int(let number): Double(number)
        default: nil
        }
    }

    /// `argument` written by C's `printf` with `format`.
    private static func c(_ format: String, _ argument: some CVarArg) -> String {
        withVaList([argument]) { arguments in
            let size = Int(vsnprintf(nil, 0, format, arguments)) + 1
            var buffer = [CChar](repeating: 0, count: size)
            return withVaList([argument]) { arguments in
                _ = vsnprintf(&buffer, size, format, arguments)
                return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
    }
}
