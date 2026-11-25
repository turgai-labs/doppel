import SwiftParser
import SwiftSyntax

/// The part of Foundation objects' code can use: its value types, as swift-foundation declares
/// them, which a file names only when it imports `Foundation` or `FoundationEssentials`, as in
/// Swift. Each is run by the evaluator with the process's own Foundation.
enum FoundationLibrary {
    /// The file its declarations are read as.
    static let file = "<Foundation>"

    /// The modules that give its types to a file that imports one.
    static let modules: Set<String> = ["Foundation", "FoundationEssentials"]

    static let source = """
        typealias TimeInterval = Double

        struct Date: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
            init()
            init(timeIntervalSinceNow: TimeInterval)
            init(timeIntervalSince1970: TimeInterval)
            init(timeIntervalSinceReferenceDate: TimeInterval)
            init(timeInterval: TimeInterval, since date: Date)
            static var now: Date { get }
            static var distantPast: Date { get }
            static var distantFuture: Date { get }
            var timeIntervalSince1970: TimeInterval { get }
            var timeIntervalSinceReferenceDate: TimeInterval { get }
            var timeIntervalSinceNow: TimeInterval { get }
            func timeIntervalSince(_ date: Date) -> TimeInterval
            func addingTimeInterval(_ timeInterval: TimeInterval) -> Date
            func advanced(by n: TimeInterval) -> Date
            func distance(to other: Date) -> TimeInterval
            var description: String { get }
        }

        struct Decimal: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
            init(_ value: Int)
            init(_ value: Double)
            init?(string: String)
            static var zero: Decimal { get }
            var description: String { get }
        }

        struct UUID: Hashable, Sendable, Codable, CustomStringConvertible {
            init()
            init?(uuidString string: String)
            var uuidString: String { get }
            var description: String { get }
        }

        struct URL: Hashable, Sendable, Codable, CustomStringConvertible {
            init?(string: String)
            var absoluteString: String { get }
            var scheme: String? { get }
            var description: String { get }
        }

        struct Data: Hashable, Sendable, Codable, CustomStringConvertible {
            init()
            init<S: Sequence>(_ elements: S) where S.Element == UInt8
            init?(base64Encoded base64String: String)
            var count: Int { get }
            var isEmpty: Bool { get }
            var startIndex: Int { get }
            var endIndex: Int { get }
            func index(after i: Int) -> Int
            func index(before i: Int) -> Int
            subscript(index: Int) -> UInt8 { get set }
            /// The bytes at the positions of a range, which reads as the data of them.
            subscript(bounds: [Int]) -> Data { get }
            mutating func append(_ byte: UInt8)
            mutating func append(_ other: Data)
            func base64EncodedString() -> String
            var description: String { get }
        }

        struct JSONDecoder {
            init()
            func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
        }

        struct JSONEncoder {
            init()
            func encode<T: Encodable>(_ value: T) throws -> Data
        }

        enum DecodingError: Error {
            struct Context: Sendable {
                let debugDescription: String
            }

            case dataCorrupted(Context)
        }

        extension Data: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
            typealias Element = UInt8
            typealias Index = Int
            typealias SubSequence = Data
        }

        extension String {
            struct Encoding: Hashable, Sendable {
                static var utf8: String.Encoding { get }
            }

            init?(data: Data, encoding: String.Encoding)
            /// Its arguments written into `format` as C's `printf` writes them.
            init(format: String, _ arguments: any CVarArg...)
            func data(using encoding: String.Encoding, allowLossyConversion: Bool = false) -> Data?
        }

        extension String: CVarArg {}
        extension Bool: CVarArg {}

        /// Unicode scalars set apart, as Foundation's sets are: its scalar values, as ranges, each
        /// from a lower bound to its upper one.
        struct CharacterSet: Hashable, Sendable {
            private let lowers: [UInt32]
            private let uppers: [UInt32]

            private init(lowers: [UInt32], uppers: [UInt32]) {
                self.lowers = lowers
                self.uppers = uppers
            }

            init(charactersIn string: String) {
                let values = string.unicodeScalars.map { $0.value }
                lowers = values
                uppers = values
            }

            /// Unicode's spaces, general category Zs, and tab.
            static var whitespaces: CharacterSet {
                CharacterSet(
                    lowers: [0x09, 0x20, 0xA0, 0x1680, 0x2000, 0x202F, 0x205F, 0x3000],
                    uppers: [0x09, 0x20, 0xA0, 0x1680, 0x200A, 0x202F, 0x205F, 0x3000])
            }

            /// Line and paragraph ends: U+000A to U+000D, U+0085, U+2028 and U+2029.
            static var newlines: CharacterSet {
                CharacterSet(lowers: [0x0A, 0x85, 0x2028], uppers: [0x0D, 0x85, 0x2029])
            }

            static var whitespacesAndNewlines: CharacterSet { whitespaces.union(newlines) }

            func contains(_ member: Unicode.Scalar) -> Bool {
                for index in 0..<lowers.count where lowers[index] <= member.value && member.value <= uppers[index] {
                    return true
                }
                return false
            }

            func union(_ other: CharacterSet) -> CharacterSet {
                CharacterSet(lowers: lowers + other.lowers, uppers: uppers + other.uppers)
            }
        }

        /// A place's rules for its clocks, by its identifier, as the process's own Foundation keeps them.
        struct TimeZone: Hashable, Sendable, Codable, CustomStringConvertible {
            let identifier: String

            init?(identifier: String) {
                guard let known = _timeZoneIdentifier(identifier) else {
                    return nil
                }
                self.identifier = known
            }

            init?(secondsFromGMT seconds: Int) {
                guard let known = _timeZoneIdentifier(secondsFromGMT: seconds) else {
                    return nil
                }
                identifier = known
            }

            fileprivate init(known identifier: String) {
                self.identifier = identifier
            }

            static var current: TimeZone { TimeZone(known: _currentTimeZone()) }
            static var gmt: TimeZone { TimeZone(known: "GMT") }

            func secondsFromGMT(for date: Date = Date()) -> Int {
                _secondsFromGMT(identifier, date)
            }

            var description: String { _timeZoneDescription(identifier) }
        }

        /// How a language and a region write things, by its identifier.
        struct Locale: Hashable, Sendable, Codable, CustomStringConvertible {
            let identifier: String

            init(identifier: String) {
                self.identifier = identifier
            }

            static var current: Locale { Locale(identifier: _currentLocale()) }

            var description: String { _localeDescription(identifier) }
        }

        /// A calendar's dates, worked out as the process's own Foundation works them out.
        struct Calendar: Hashable, Sendable, Codable {
            enum Identifier: Hashable, Sendable, Codable {
                case gregorian
                case iso8601
            }

            enum Component: Hashable, Sendable {
                case era
                case year
                case month
                case day
                case hour
                case minute
                case second
                case weekday
                case weekdayOrdinal
                case quarter
                case weekOfMonth
                case weekOfYear
                case yearForWeekOfYear
                case nanosecond
                case dayOfYear
                case calendar
                case timeZone
            }

            let identifier: Identifier
            var timeZone: TimeZone
            var locale: Locale?
            var firstWeekday: Int
            var minimumDaysInFirstWeek: Int

            init(identifier: Identifier) {
                self.identifier = identifier
                timeZone = TimeZone.current
                locale = nil
                firstWeekday = _calendarFirstWeekday(identifier == .iso8601)
                minimumDaysInFirstWeek = _calendarMinimumDaysInFirstWeek(identifier == .iso8601)
            }

            static var current: Calendar {
                var calendar = Calendar(identifier: _currentCalendarIsISO8601() ? .iso8601 : .gregorian)
                calendar.locale = Locale.current
                calendar.firstWeekday = _currentFirstWeekday()
                calendar.minimumDaysInFirstWeek = _currentMinimumDaysInFirstWeek()
                return calendar
            }

            func date(byAdding component: Component, value: Int, to date: Date, wrappingComponents: Bool = false) -> Date? {
                var components = DateComponents()
                components.setValue(value, for: component)
                return _calendarAdding(self, components, date, wrappingComponents)
            }

            func date(byAdding components: DateComponents, to date: Date, wrappingComponents: Bool = false) -> Date? {
                _calendarAdding(self, components, date, wrappingComponents)
            }

            func component(_ component: Component, from date: Date) -> Int {
                _calendarComponents(self, [component], date).value(for: component) ?? 0
            }

            func dateComponents(_ components: Set<Component>, from date: Date) -> DateComponents {
                _calendarComponents(self, components, date)
            }

            func dateComponents(_ components: Set<Component>, from start: Date, to end: Date) -> DateComponents {
                _calendarDifference(self, components, start, end)
            }

            func date(from components: DateComponents) -> Date? {
                _calendarDate(self, components)
            }

            func startOfDay(for date: Date) -> Date {
                _calendarStartOfDay(self, date)
            }

            func isDate(_ date1: Date, inSameDayAs date2: Date) -> Bool {
                _calendarSameDay(self, date1, date2)
            }

            func isDateInToday(_ date: Date) -> Bool {
                _calendarIs(self, "today", date)
            }

            func isDateInYesterday(_ date: Date) -> Bool {
                _calendarIs(self, "yesterday", date)
            }

            func isDateInTomorrow(_ date: Date) -> Bool {
                _calendarIs(self, "tomorrow", date)
            }

            func isDateInWeekend(_ date: Date) -> Bool {
                _calendarIs(self, "weekend", date)
            }

            var weekdaySymbols: [String] { _calendarSymbols(self, "weekday") }
            var shortWeekdaySymbols: [String] { _calendarSymbols(self, "shortWeekday") }
            var monthSymbols: [String] { _calendarSymbols(self, "month") }
            var shortMonthSymbols: [String] { _calendarSymbols(self, "shortMonth") }
        }

        /// A date or a length of time in units of a calendar, each one given or not.
        struct DateComponents: Hashable, Sendable, Codable, CustomStringConvertible {
            var calendar: Calendar?
            var timeZone: TimeZone?
            var era: Int?
            var year: Int?
            var month: Int?
            var day: Int?
            var hour: Int?
            var minute: Int?
            var second: Int?
            var nanosecond: Int?
            var weekday: Int?
            var weekdayOrdinal: Int?
            var quarter: Int?
            var weekOfMonth: Int?
            var weekOfYear: Int?
            var yearForWeekOfYear: Int?
            var dayOfYear: Int?

            init(
                calendar: Calendar? = nil, timeZone: TimeZone? = nil, era: Int? = nil, year: Int? = nil,
                month: Int? = nil, day: Int? = nil, hour: Int? = nil, minute: Int? = nil, second: Int? = nil,
                nanosecond: Int? = nil, weekday: Int? = nil, weekdayOrdinal: Int? = nil, quarter: Int? = nil,
                weekOfMonth: Int? = nil, weekOfYear: Int? = nil, yearForWeekOfYear: Int? = nil
            ) {
                self.calendar = calendar
                self.timeZone = timeZone
                self.era = era
                self.year = year
                self.month = month
                self.day = day
                self.hour = hour
                self.minute = minute
                self.second = second
                self.nanosecond = nanosecond
                self.weekday = weekday
                self.weekdayOrdinal = weekdayOrdinal
                self.quarter = quarter
                self.weekOfMonth = weekOfMonth
                self.weekOfYear = weekOfYear
                self.yearForWeekOfYear = yearForWeekOfYear
            }

            /// The date its calendar makes of it, in its time zone when it has one.
            var date: Date? {
                guard let calendar else {
                    return nil
                }
                return calendar.date(from: self)
            }

            func value(for component: Calendar.Component) -> Int? {
                switch component {
                case .era: return era
                case .year: return year
                case .month: return month
                case .day: return day
                case .hour: return hour
                case .minute: return minute
                case .second: return second
                case .weekday: return weekday
                case .weekdayOrdinal: return weekdayOrdinal
                case .quarter: return quarter
                case .weekOfMonth: return weekOfMonth
                case .weekOfYear: return weekOfYear
                case .yearForWeekOfYear: return yearForWeekOfYear
                case .nanosecond: return nanosecond
                case .dayOfYear: return dayOfYear
                case .calendar, .timeZone: return nil
                }
            }

            mutating func setValue(_ value: Int?, for component: Calendar.Component) {
                switch component {
                case .era: era = value
                case .year: year = value
                case .month: month = value
                case .day: day = value
                case .hour: hour = value
                case .minute: minute = value
                case .second: second = value
                case .weekday: weekday = value
                case .weekdayOrdinal: weekdayOrdinal = value
                case .quarter: quarter = value
                case .weekOfMonth: weekOfMonth = value
                case .weekOfYear: weekOfYear = value
                case .yearForWeekOfYear: yearForWeekOfYear = value
                case .nanosecond: nanosecond = value
                case .dayOfYear: dayOfYear = value
                case .calendar, .timeZone: break
                }
            }

            var description: String { _dateComponentsDescription(self) }
        }

        extension Date {
            /// It as ISO 8601 writes it, in GMT: `2026-11-25T21:30:00Z`.
            func ISO8601Format() -> String {
                _iso8601(self)
            }
        }

        fileprivate func _timeZoneIdentifier(_ identifier: String) -> String?
        fileprivate func _timeZoneIdentifier(secondsFromGMT seconds: Int) -> String?
        fileprivate func _currentTimeZone() -> String
        fileprivate func _secondsFromGMT(_ identifier: String, _ date: Date) -> Int
        fileprivate func _timeZoneDescription(_ identifier: String) -> String
        fileprivate func _currentLocale() -> String
        fileprivate func _localeDescription(_ identifier: String) -> String
        fileprivate func _currentCalendarIsISO8601() -> Bool
        fileprivate func _currentFirstWeekday() -> Int
        fileprivate func _currentMinimumDaysInFirstWeek() -> Int
        fileprivate func _calendarFirstWeekday(_ iso8601: Bool) -> Int
        fileprivate func _calendarMinimumDaysInFirstWeek(_ iso8601: Bool) -> Int
        fileprivate func _calendarAdding(_ calendar: Calendar, _ components: DateComponents, _ date: Date, _ wrapping: Bool) -> Date?
        fileprivate func _calendarComponents(_ calendar: Calendar, _ components: Set<Calendar.Component>, _ date: Date) -> DateComponents
        fileprivate func _calendarDifference(_ calendar: Calendar, _ components: Set<Calendar.Component>, _ start: Date, _ end: Date) -> DateComponents
        fileprivate func _calendarDate(_ calendar: Calendar, _ components: DateComponents) -> Date?
        fileprivate func _calendarStartOfDay(_ calendar: Calendar, _ date: Date) -> Date
        fileprivate func _calendarSameDay(_ calendar: Calendar, _ date1: Date, _ date2: Date) -> Bool
        fileprivate func _calendarIs(_ calendar: Calendar, _ question: String, _ date: Date) -> Bool
        fileprivate func _calendarSymbols(_ calendar: Calendar, _ which: String) -> [String]
        fileprivate func _dateComponentsDescription(_ components: DateComponents) -> String
        fileprivate func _iso8601(_ date: Date) -> String

        extension StringProtocol {
            /// It without the scalars in `set` at either end.
            func trimmingCharacters(in set: CharacterSet) -> String {
                let scalars = unicodeScalars
                var start = 0
                var end = scalars.count
                while start < end && set.contains(scalars[start]) {
                    start += 1
                }
                while end > start && set.contains(scalars[end - 1]) {
                    end -= 1
                }
                var trimmed = ""
                for index in start..<end {
                    trimmed.unicodeScalars.append(scalars[index])
                }
                return trimmed
            }
        }
        """

    /// Its Swift, its operators folded by precedence, as every file's are.
    static let syntax: SourceFileSyntax = SwiftCheck.folded(Parser.parse(source: source))

    /// The names it declares, which a file that doesn't import it can't name.
    static let typeNames: Set<String> = Set(syntax.statements.compactMap { Module.declaredName($0.item) })
}
