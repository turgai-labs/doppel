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
    static let foundationTypes: Set<String> = ["Date", "Decimal", "UUID", "URL"]

    /// A static member of one of its types: `Date.now`.
    func foundationStatic(_ type: String, _ name: String) throws -> Value {
        switch (type, name) {
        case ("Date", "now"): return .date(.now)
        case ("Date", "distantPast"): return .date(.distantPast)
        case ("Date", "distantFuture"): return .date(.distantFuture)
        case ("Decimal", "zero"): return .decimal(.zero)
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
        default: nil
        }
    }

    // MARK: Crossing

    /// One of its values as it crosses, as the actors that send it write it: a date as ISO 8601
    /// with this device's offset, a decimal as a number, a UUID and a URL as text.
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
