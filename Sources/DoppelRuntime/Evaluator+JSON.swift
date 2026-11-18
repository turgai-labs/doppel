import Doppel

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// `JSONDecoder` and `JSONEncoder`, as `FoundationLibrary` declares them: JSON read and written
/// with the process's own coders, and a value read as its type as `Codable` reads it.
extension Evaluator {
    /// The coders it runs; neither holds anything.
    static let jsonCoders: Set<String> = ["JSONDecoder", "JSONEncoder"]

    /// A coder's member: `decode(_:from:)`, `encode(_:)`.
    func json(_ coder: String, _ name: String, _ arguments: [Value]) throws -> Value {
        switch (coder, name) {
        case ("JSONDecoder", "decode(_:from:)"):
            guard case .metatype(let type) = arguments[0], case .data(let bytes) = arguments[1] else { break }
            let read: Portable
            do {
                read = try JSONPortable.read(bytes)
            } catch {
                throw try thrown(Self.decodingError("The given data was not valid JSON."))
            }
            do {
                return try value(read, as: type)
            } catch let trap as Trap {
                // What doesn't fit its type is thrown as Swift's decoder throws it, said with where it is.
                throw try thrown(Self.decodingError(trap.message))
            }
        case ("JSONEncoder", "encode(_:)"):
            do {
                return .data(try JSONPortable.write(try portable(arguments[0], as: .dynamic)))
            } catch let trap as Trap {
                throw trap
            } catch {
                throw Trap(message: "It can't be written as JSON: \(error)")
            }
        default: break
        }
        throw Trap(message: "'\(coder).\(name)' isn't run by Doppel yet")
    }

    /// The error a decode throws: `DecodingError.dataCorrupted`, saying why.
    private static func decodingError(_ why: String) -> Value {
        .enumCase("DecodingError", "dataCorrupted", [.structure("DecodingError.Context", [.string(why)])])
    }
}

/// A portable value as JSON has it, read and written with the process's own coders.
private struct JSONPortable: Codable {
    let value: Portable

    init(_ value: Portable) {
        self.value = value
    }

    static func read(_ bytes: Data) throws -> Portable {
        try JSONDecoder().decode(JSONPortable.self, from: bytes).value
    }

    static func write(_ value: Portable) throws -> Data {
        try JSONEncoder().encode(JSONPortable(value))
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(_ name: String) {
            stringValue = name
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    init(from decoder: any Decoder) throws {
        if let object = try? decoder.container(keyedBy: Key.self) {
            value = .object(
                try object.allKeys.map { ($0.stringValue, try object.decode(JSONPortable.self, forKey: $0).value) })
        } else if var array = try? decoder.unkeyedContainer() {
            var elements: [Portable] = []
            while !array.isAtEnd { elements.append(try array.decode(JSONPortable.self).value) }
            value = .array(elements)
        } else {
            let single = try decoder.singleValueContainer()
            if single.decodeNil() {
                value = .null
            } else if let flag = try? single.decode(Bool.self) {
                value = .bool(flag)
            } else if let number = try? single.decode(Int.self) {
                value = .int(number)
            } else if let number = try? single.decode(Double.self) {
                value = .double(number)
            } else {
                value = .string(try single.decode(String.self))
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch value {
        case .null:
            var single = encoder.singleValueContainer()
            try single.encodeNil()
        case .bool(let flag):
            var single = encoder.singleValueContainer()
            try single.encode(flag)
        case .int(let number):
            var single = encoder.singleValueContainer()
            try single.encode(number)
        case .double(let number):
            var single = encoder.singleValueContainer()
            try single.encode(number)
        case .string(let text):
            var single = encoder.singleValueContainer()
            try single.encode(text)
        case .array(let elements):
            var array = encoder.unkeyedContainer()
            for element in elements { try array.encode(JSONPortable(element)) }
        case .object(let members):
            var object = encoder.container(keyedBy: Key.self)
            for (name, member) in members { try object.encode(JSONPortable(member), forKey: Key(name)) }
        case .reference:
            throw Trap(message: "An object can't be written as JSON.")
        }
    }
}
