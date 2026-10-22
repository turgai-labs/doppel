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
        """

    /// Its Swift, its operators folded by precedence, as every file's are.
    static let syntax: SourceFileSyntax = SwiftCheck.folded(Parser.parse(source: source))

    /// The names it declares, which a file that doesn't import it can't name.
    static let typeNames: Set<String> = Set(syntax.statements.compactMap { Module.declaredName($0.item) })
}
