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
            func data(using encoding: String.Encoding, allowLossyConversion: Bool = false) -> Data?
        }

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
