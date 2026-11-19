import Doppel

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// Foundation's value types, as `FoundationLibrary` declares them, each run with the process's own
/// Foundation: what code reads of them is what Swift's gives.
extension Evaluator {
    /// The types it runs.
    static let foundationTypes: Set<String> = ["Date", "Decimal", "UUID", "URL", "Data", "String.Encoding"]

    /// A static member of one of its types: `Date.now`.
    func foundationStatic(_ type: String, _ name: String) throws -> Value {
        switch (type, name) {
        case ("Date", "now"): return .date(.now)
        case ("Date", "distantPast"): return .date(.distantPast)
        case ("Date", "distantFuture"): return .date(.distantFuture)
        case ("Decimal", "zero"): return .decimal(.zero)
        case ("String.Encoding", "utf8"): return Self.encoding(.utf8)
        default: throw Trap(message: "'\(type).\(name)' isn't run by Doppel yet")
        }
    }

    /// One of its types made: `Date(timeIntervalSince1970: 0)`, `URL(string: text)`.
    func foundationInitializer(_ type: String, _ name: String, _ arguments: [Value]) throws -> Value {
        switch (type, name, arguments.first) {
        case ("Date", "init()", nil): return .date(Date())
        case ("Date", "init(timeIntervalSinceNow:)", .double(let seconds)?):
            return .date(Date(timeIntervalSinceNow: seconds))
        case ("Date", "init(timeIntervalSince1970:)", .double(let seconds)?):
            return .date(Date(timeIntervalSince1970: seconds))
        case ("Date", "init(timeIntervalSinceReferenceDate:)", .double(let seconds)?):
            return .date(Date(timeIntervalSinceReferenceDate: seconds))
        case ("Date", "init(timeInterval:since:)", .double(let seconds)?):
            guard case .date(let date) = arguments[1] else { break }
            return .date(Date(timeInterval: seconds, since: date))
        case ("Decimal", "init(_:)", .int(let number)?): return .decimal(Decimal(number))
        case ("Decimal", "init(_:)", .double(let number)?): return .decimal(Decimal(number))
        case ("Decimal", "init(string:)", .string(let text)?):
            return .optional(Decimal(string: text).map(Value.decimal))
        case ("UUID", "init()", nil): return .uuid(UUID())
        case ("UUID", "init(uuidString:)", .string(let text)?): return .optional(UUID(uuidString: text).map(Value.uuid))
        case ("URL", "init(string:)", .string(let text)?): return .optional(URL(string: text).map(Value.url))
        case ("Data", "init()", nil): return .data(Data())
        case ("Data", "init(_:)", .data(let bytes)?): return .data(Data(bytes))
        case ("Data", "init(_:)", let source?): return .data(Data(try elements(of: source).map(Self.byte)))
        case ("Data", "init(base64Encoded:)", .string(let text)?):
            return .optional(Data(base64Encoded: text).map(Value.data))
        default: break
        }
        throw Trap(message: "'\(type).\(name)' isn't run by Doppel yet")
    }

    /// A member of one of its values: `date.timeIntervalSince1970`, `url.absoluteString`.
    func foundationMember(_ name: String, of value: Value, _ arguments: [Value]) throws -> Value? {
        switch value {
        case .date(let date):
            switch (name, arguments.first) {
            case ("timeIntervalSince1970", nil): return .double(date.timeIntervalSince1970)
            case ("timeIntervalSinceReferenceDate", nil): return .double(date.timeIntervalSinceReferenceDate)
            case ("timeIntervalSinceNow", nil): return .double(date.timeIntervalSinceNow)
            case ("timeIntervalSince(_:)", .date(let other)?): return .double(date.timeIntervalSince(other))
            case ("addingTimeInterval(_:)", .double(let seconds)?): return .date(date.addingTimeInterval(seconds))
            case ("advanced(by:)", .double(let seconds)?): return .date(date.advanced(by: seconds))
            case ("distance(to:)", .date(let other)?): return .double(date.distance(to: other))
            case ("description", nil): return .string(date.description)
            default: return nil
            }
        case .decimal(let decimal):
            return name == "description" ? .string(decimal.description) : nil
        case .uuid(let uuid):
            switch name {
            case "uuidString", "description": return .string(uuid.uuidString)
            default: return nil
            }
        case .url(let url):
            switch name {
            case "absoluteString", "description": return .string(url.absoluteString)
            case "scheme": return .optional(url.scheme.map(Value.string))
            default: return nil
            }
        case .data(let bytes):
            switch (name, arguments.first) {
            case ("count", nil): return .int(bytes.count)
            case ("isEmpty", nil): return .bool(bytes.isEmpty)
            // Its own positions, as Foundation's: a slice's start where it was in what it's of.
            case ("startIndex", nil): return .int(bytes.startIndex)
            case ("endIndex", nil): return .int(bytes.endIndex)
            case ("index(after:)", .int(let index)?): return .int(bytes.index(after: index))
            case ("index(before:)", .int(let index)?): return .int(bytes.index(before: index))
            case ("subscript(_:)", .int(let index)?):
                guard bytes.indices.contains(index) else { throw Trap(message: "Index out of range") }
                return Self.byte(bytes[index])
            case ("subscript(_:)", .array(let positions)?):
                // The positions of a range, read as the array of them: the bytes there.
                let indices = try positions.map(int)
                guard let first = indices.first else { return .data(Data()) }
                guard indices.allSatisfy(bytes.indices.contains) else {
                    throw Trap(message: "Data index is out of range")
                }
                return .data(bytes[first..<first + indices.count])
            case ("base64EncodedString()", nil): return .string(bytes.base64EncodedString())
            case ("description", nil): return .string(bytes.description)
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Its operators: a date moved by seconds, and decimal arithmetic.
    func foundationBinary(_ op: String, _ lhs: Value, _ rhs: Value) -> Value? {
        switch (op, lhs, rhs) {
        case ("+", .date(let date), .double(let seconds)): return .date(date + seconds)
        case ("-", .date(let date), .double(let seconds)): return .date(date - seconds)
        case ("+", .decimal(let a), .decimal(let b)): return .decimal(a + b)
        case ("-", .decimal(let a), .decimal(let b)): return .decimal(a - b)
        case ("*", .decimal(let a), .decimal(let b)): return .decimal(a * b)
        case ("/", .decimal(let a), .decimal(let b)): return .decimal(a / b)
        default: return nil
        }
    }

    static func foundationEqual(_ lhs: Value, _ rhs: Value) -> Bool? {
        switch (lhs, rhs) {
        case (.date(let a), .date(let b)): a == b
        case (.decimal(let a), .decimal(let b)): a == b
        case (.uuid(let a), .uuid(let b)): a == b
        case (.url(let a), .url(let b)): a == b
        case (.data(let a), .data(let b)): a == b
        default: nil
        }
    }

    static func foundationCompare(_ lhs: Value, _ rhs: Value) -> Int? {
        switch (lhs, rhs) {
        case (.date(let a), .date(let b)): a < b ? -1 : a > b ? 1 : 0
        case (.decimal(let a), .decimal(let b)): a < b ? -1 : a > b ? 1 : 0
        default: nil
        }
    }

    /// As `String(describing:)` writes one.
    static func foundationDescription(_ value: Value) -> String? {
        switch value {
        case .date(let date): date.description
        case .decimal(let decimal): decimal.description
        case .uuid(let uuid): uuid.uuidString
        case .url(let url): url.absoluteString
        case .data(let bytes): bytes.description
        default: nil
        }
    }

    /// Foundation's own members of `String`: text read from data, and written as data.
    func foundationString(_ name: String, _ text: Value?, _ arguments: [Value]) throws -> Value {
        switch (name, text, arguments.first) {
        case ("init(format:_:)", nil, .string(let format)?):
            guard case .array(let values) = arguments[1] else { throw Trap(message: "not the format's arguments") }
            return .string(try formatted(format, values))
        case ("init(data:encoding:)", nil, .data(let bytes)?):
            return .optional(String(data: bytes, encoding: try Self.encoding(arguments[1])).map(Value.string))
        case ("data(using:allowLossyConversion:)", .string(let text)?, let encoding?):
            guard case .bool(let lossy) = arguments[1] else { throw Trap(message: "not a Bool") }
            return .optional(text.data(using: try Self.encoding(encoding), allowLossyConversion: lossy).map(Value.data))
        default: throw Trap(message: "'String.\(name)' isn't run by Doppel yet")
        }
    }

    /// A string encoding, as its raw value.
    static func encoding(_ encoding: String.Encoding) -> Value {
        .structure("String.Encoding", [.fixed(.uint, UInt64(encoding.rawValue))])
    }

    static func encoding(_ value: Value) throws -> String.Encoding {
        guard case .structure("String.Encoding", let fields) = value, case .fixed(.uint, let raw)? = fields.first else {
            throw Trap(message: "not a String.Encoding")
        }
        return String.Encoding(rawValue: UInt(raw))
    }

    /// Data with a byte, or other data, appended.
    static func appending(_ appended: Value, to bytes: Data) throws -> Value {
        var bytes = bytes
        if case .data(let other) = appended { bytes.append(other) } else { bytes.append(try byte(appended)) }
        return .data(bytes)
    }

    /// Data with the byte at a position set.
    static func setting(_ index: Int, of bytes: Data, to value: Value) throws -> Value {
        guard bytes.indices.contains(index) else { throw Trap(message: "Index out of range") }
        var bytes = bytes
        bytes[index] = try byte(value)
        return .data(bytes)
    }

    /// A byte, as `UInt8`.
    static func byte(_ byte: UInt8) -> Value { .fixed(.uint8, UInt64(byte)) }

    static func byte(_ value: Value) throws -> UInt8 {
        guard case .fixed(.uint8, let bits) = value else { throw Trap(message: "not a UInt8") }
        return UInt8(bits)
    }

    // MARK: Crossing

    /// One of its values as it crosses, as the actors that send it write it: a date as ISO 8601
    /// with this device's offset, a decimal as a number, a UUID and a URL as text, data as
    /// base64 text, as `JSONEncoder` writes it.
    static func foundationPortable(_ value: Value) -> Portable? {
        switch value {
        case .date(let date):
            let seconds = date.timeIntervalSince1970
            return .string(
                date.formatted(
                    Date.ISO8601FormatStyle(
                        includingFractionalSeconds: seconds.rounded(.down) != seconds, timeZone: .current)))
        case .decimal(let decimal): return .double(Double(decimal.description) ?? 0)
        case .uuid(let uuid): return .string(uuid.uuidString)
        case .url(let url): return .string(url.absoluteString)
        case .data(let bytes): return .string(bytes.base64EncodedString())
        default: return nil
        }
    }

    /// A portable value read as one of its types; `nil` when `type` isn't one of them.
    static func foundationValue(_ portable: Portable, as type: String) throws -> Value? {
        switch (type, portable) {
        case ("Date", .string(let text)):
            guard
                let date = (try? Date(text, strategy: .iso8601))
                    ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                    ?? localDateTime(text)
            else {
                throw Trap(
                    message: "\"\(text)\" isn't a 'Date': a date and time such as 2026-10-01T09:00, or with an offset")
            }
            return .date(date)
        case ("Decimal", .int(let number)): return .decimal(Decimal(number))
        case ("Decimal", .double(let number)): return .decimal(Decimal(string: "\(number)") ?? Decimal(number))
        case ("UUID", .string(let text)):
            guard let uuid = UUID(uuidString: text) else { throw Trap(message: "\"\(text)\" isn't a 'UUID'") }
            return .uuid(uuid)
        case ("URL", .string(let text)):
            guard let url = URL(string: text) else { throw Trap(message: "\"\(text)\" isn't a 'URL'") }
            return .url(url)
        case ("Data", .string(let text)):
            guard let bytes = Data(base64Encoded: text) else {
                throw Trap(message: "Encountered Data is not valid Base64.")
            }
            return .data(bytes)
        case (_, _) where foundationTypes.contains(type):
            throw Trap(message: "\(portable) isn't a '\(type)'")
        default:
            return nil
        }
    }

    /// A date and time without an offset, such as `2026-10-01T09:00`: this device's local time.
    private static func localDateTime(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "T" || $0 == " " })
        guard parts.count == 2 else { return nil }
        let day = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].split(separator: ":").compactMap { Int($0) }
        guard day.count == 3, (2...3).contains(time.count),
            parts[0].split(separator: "-").count == 3, parts[1].split(separator: ":").count == time.count
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(
            year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1],
            second: time.count == 3 ? time[2] : 0)
        guard let date = calendar.date(from: components),
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                == DateComponents(year: day[0], month: day[1], day: day[2], hour: time[0], minute: time[1])
        else { return nil }
        return date
    }
}
