import Doppel

#if canImport(FoundationEssentials)
    import FoundationEssentials
    #if canImport(FoundationInternationalization)
        import FoundationInternationalization
    #endif
#else
    import Foundation
#endif

/// Foundation's calendars, time zones and locales, as `FoundationLibrary` declares them: its Swift
/// holds what they are, and what's worked out of them is worked out here, with the process's own
/// Foundation, so what code reads is what Swift's gives.
extension Evaluator {
    /// One of the functions `FoundationLibrary` keeps to itself, by its name, or `nil` for any
    /// other.
    func foundationGlobal(_ name: String, _ arguments: [Value]) throws -> Value? {
        switch name {
        case "_timeZoneIdentifier(_:)":
            return .optional(TimeZone(identifier: try string(arguments[0])).map { .string($0.identifier) })
        case "_timeZoneIdentifier(secondsFromGMT:)":
            return .optional(TimeZone(secondsFromGMT: try int(arguments[0])).map { .string($0.identifier) })
        case "_currentTimeZone()": return .string(TimeZone.current.identifier)
        case "_secondsFromGMT(_:_:)":
            return .int(try Self.timeZone(named: try string(arguments[0])).secondsFromGMT(for: try date(arguments[1])))
        case "_timeZoneDescription(_:)": return .string(try Self.timeZone(named: try string(arguments[0])).description)
        case "_currentLocale()": return .string(Locale.current.identifier)
        case "_localeDescription(_:)": return .string(Locale(identifier: try string(arguments[0])).description)
        case "_currentCalendarIsISO8601()": return .bool(Calendar.current.identifier == .iso8601)
        case "_currentFirstWeekday()": return .int(Calendar.current.firstWeekday)
        case "_currentMinimumDaysInFirstWeek()": return .int(Calendar.current.minimumDaysInFirstWeek)
        case "_calendarFirstWeekday(_:)":
            return .int(Calendar(identifier: try truth(of: arguments[0]) ? .iso8601 : .gregorian).firstWeekday)
        case "_calendarMinimumDaysInFirstWeek(_:)":
            return .int(
                Calendar(identifier: try truth(of: arguments[0]) ? .iso8601 : .gregorian).minimumDaysInFirstWeek)
        case "_calendarAdding(_:_:_:_:)":
            let added = try calendar(arguments[0]).date(
                byAdding: try dateComponents(arguments[1]), to: try date(arguments[2]),
                wrappingComponents: try truth(of: arguments[3]))
            return .optional(added.map(Value.date))
        case "_calendarComponents(_:_:_:)":
            let calendar = try calendar(arguments[0])
            return dateComponentsValue(
                calendar.dateComponents(try components(arguments[1]), from: try date(arguments[2])))
        case "_calendarDifference(_:_:_:_:)":
            let calendar = try calendar(arguments[0])
            return dateComponentsValue(
                calendar.dateComponents(
                    try components(arguments[1]), from: try date(arguments[2]), to: try date(arguments[3])))
        case "_calendarDate(_:_:)":
            return .optional(try calendar(arguments[0]).date(from: try dateComponents(arguments[1])).map(Value.date))
        case "_calendarStartOfDay(_:_:)":
            return .date(try calendar(arguments[0]).startOfDay(for: try date(arguments[1])))
        case "_calendarSameDay(_:_:_:)":
            return .bool(try calendar(arguments[0]).isDate(try date(arguments[1]), inSameDayAs: try date(arguments[2])))
        case "_calendarIs(_:_:_:)":
            let calendar = try calendar(arguments[0])
            let date = try date(arguments[2])
            switch try string(arguments[1]) {
            case "today": return .bool(calendar.isDateInToday(date))
            case "yesterday": return .bool(calendar.isDateInYesterday(date))
            case "tomorrow": return .bool(calendar.isDateInTomorrow(date))
            case "weekend": return .bool(calendar.isDateInWeekend(date))
            default: return nil
            }
        case "_calendarSymbols(_:_:)":
            let calendar = try calendar(arguments[0])
            let symbols: [String]
            switch try string(arguments[1]) {
            case "weekday": symbols = calendar.weekdaySymbols
            case "shortWeekday": symbols = calendar.shortWeekdaySymbols
            case "month": symbols = calendar.monthSymbols
            case "shortMonth": symbols = calendar.shortMonthSymbols
            default: return nil
            }
            return .array(symbols.map(Value.string))
        case "_dateComponentsDescription(_:)": return .string(try dateComponents(arguments[0]).description)
        case "_iso8601(_:)": return .string(try date(arguments[0]).ISO8601Format())
        default: return nil
        }
    }

    // MARK: From what code holds

    private func date(_ value: Value) throws -> Date {
        guard case .date(let date) = value else { throw Trap(message: "not a Date") }
        return date
    }

    /// `value`'s stored properties, by name, as its type declares them.
    private func stored(_ value: Value) throws -> [String: Value] {
        guard case .structure(let type, let fields) = value, let names = program.type(named: type)?.storedNames else {
            throw Trap(message: "not a value with properties")
        }
        return Dictionary(uniqueKeysWithValues: zip(names, fields))
    }

    private static func timeZone(named identifier: String) throws -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else { throw Trap(message: "no time zone '\(identifier)'") }
        return zone
    }

    private func timeZone(_ value: Value) throws -> TimeZone {
        try Self.timeZone(named: try string(try stored(value)["identifier"] ?? .void))
    }

    private func calendar(_ value: Value) throws -> Calendar {
        let fields = try stored(value)
        guard case .enumCase(_, let identifier, _)? = fields["identifier"] else {
            throw Trap(message: "not a Calendar")
        }
        var calendar = Calendar(identifier: identifier == "iso8601" ? .iso8601 : .gregorian)
        calendar.timeZone = try timeZone(fields["timeZone"] ?? .void)
        if case .optional(let locale?)? = fields["locale"] {
            calendar.locale = Locale(identifier: try string(try stored(locale)["identifier"] ?? .void))
        }
        calendar.firstWeekday = try int(fields["firstWeekday"] ?? .void)
        calendar.minimumDaysInFirstWeek = try int(fields["minimumDaysInFirstWeek"] ?? .void)
        return calendar
    }

    private func components(_ value: Value) throws -> Set<Calendar.Component> {
        guard case .set(let elements) = value else { throw Trap(message: "not a Set") }
        return Set(try elements.map(Self.component))
    }

    private static func component(_ value: Value) throws -> Calendar.Component {
        guard case .enumCase(_, let name, _) = value, let component = components[name] else {
            throw Trap(message: "not a Calendar.Component")
        }
        return component
    }

    /// Each component by the name its case has.
    private static let components: [String: Calendar.Component] = [
        "era": .era, "year": .year, "month": .month, "day": .day, "hour": .hour, "minute": .minute, "second": .second,
        "weekday": .weekday, "weekdayOrdinal": .weekdayOrdinal, "quarter": .quarter, "weekOfMonth": .weekOfMonth,
        "weekOfYear": .weekOfYear, "yearForWeekOfYear": .yearForWeekOfYear, "nanosecond": .nanosecond,
        "dayOfYear": .dayOfYear, "calendar": .calendar, "timeZone": .timeZone,
    ]

    /// The integer components `DateComponents` holds, each by the name of its property, which is
    /// its component's.
    private static let integerComponents: [(name: String, component: Calendar.Component)] =
        components
        .filter { $0.value != .calendar && $0.value != .timeZone }.map { ($0.key, $0.value) }

    private func dateComponents(_ value: Value) throws -> DateComponents {
        let fields = try stored(value)
        var components = DateComponents()
        if case .optional(let calendar?)? = fields["calendar"] { components.calendar = try self.calendar(calendar) }
        if case .optional(let zone?)? = fields["timeZone"] { components.timeZone = try timeZone(zone) }
        for (name, component) in Self.integerComponents {
            if case .optional(let number?)? = fields[name] { components.setValue(try int(number), for: component) }
        }
        return components
    }

    // MARK: To what code holds

    private func made(_ type: String, _ fields: [String: Value]) -> Value {
        let names = program.type(named: type)?.storedNames ?? []
        return .structure(type, names.map { fields[$0] ?? .optional(nil) })
    }

    private func timeZoneValue(_ zone: TimeZone) -> Value {
        made("TimeZone", ["identifier": .string(zone.identifier)])
    }

    private func calendarValue(_ calendar: Calendar) -> Value {
        made(
            "Calendar",
            [
                "identifier": .enumCase(
                    "Calendar.Identifier", calendar.identifier == .iso8601 ? "iso8601" : "gregorian", []),
                "timeZone": timeZoneValue(calendar.timeZone),
                "locale": .optional(calendar.locale.map { made("Locale", ["identifier": .string($0.identifier)]) }),
                "firstWeekday": .int(calendar.firstWeekday),
                "minimumDaysInFirstWeek": .int(calendar.minimumDaysInFirstWeek),
            ])
    }

    private func dateComponentsValue(_ components: DateComponents) -> Value {
        var fields: [String: Value] = [
            "calendar": .optional(components.calendar.map(calendarValue)),
            "timeZone": .optional(components.timeZone.map(timeZoneValue)),
        ]
        for (name, component) in Self.integerComponents {
            fields[name] = .optional(components.value(for: component).map(Value.int))
        }
        return made("DateComponents", fields)
    }
}
