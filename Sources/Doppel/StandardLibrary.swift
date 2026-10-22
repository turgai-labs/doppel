/// The part of Swift's standard library objects' code can use, as Swift declares it: read like any
/// module's declarations, so a type's members are known by declaring them here. Each is run by the
/// evaluator's own implementation of it.
///
/// Where Swift's own type is a view, such as a dictionary's `keys`, it's declared as the array it
/// reads as.
enum StandardLibrary {
    static let source = """
        protocol Equatable {}
        protocol Hashable: Equatable {}
        protocol Comparable: Equatable {}
        protocol Sendable {}
        protocol Error: Sendable {}
        protocol Actor: Sendable {}
        protocol CustomStringConvertible {}
        protocol Codable {}
        protocol Identifiable {}
        protocol CaseIterable {}
        protocol BinaryInteger: Hashable, Comparable, CustomStringConvertible {}
        protocol FixedWidthInteger: BinaryInteger {}

        struct Int: Sendable, Codable, FixedWidthInteger {}

        struct Double: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
            init(_ value: Double)
            init(_ value: Int)
            init<T: BinaryInteger>(_ value: T)
            init?(_ text: String)
            var description: String { get }
            func rounded() -> Double
        }

        struct Bool: Hashable, Sendable, Codable, CustomStringConvertible {
            var description: String { get }
            mutating func toggle()
        }

        struct String: StringProtocol, Sendable, Codable {
            /// A position in a string: where a character is.
            struct Index: Comparable, Hashable {}

            init()
            init(_ value: Int)
            init(_ value: Double)
            init(_ character: Character)
            init(_ scalar: Unicode.Scalar)
            init<S: Sequence>(_ characters: S) where S.Element == Character
            init<T: BinaryInteger>(_ value: T, radix: Int = 10, uppercase: Bool = false)
            init(repeating repeatedValue: String, count: Int)
            init(repeating repeatedValue: Character, count: Int)
            init(describing value: Any)
            mutating func append(_ other: String)
            mutating func append(_ character: Character)
            mutating func removeFirst() -> Character
            mutating func removeFirst(_ k: Int)
            mutating func removeLast() -> Character
            mutating func removeLast(_ k: Int)
            mutating func removeAll()
        }

        /// Part of a string: what slicing one makes.
        struct Substring: StringProtocol, Sendable {
            init()
            init<S: Sequence>(_ characters: S) where S.Element == Character
            mutating func append(_ character: Character)
        }

        /// Unicode's names for what text is made of.
        struct Unicode {
            /// One Unicode scalar value: a code point.
            struct Scalar: Hashable, Comparable, CustomStringConvertible {
                /// Its properties, as Unicode gives them.
                struct Properties {
                    var isAlphabetic: Bool { get }
                    var isWhitespace: Bool { get }
                    var isUppercase: Bool { get }
                    var isLowercase: Bool { get }
                    var isEmoji: Bool { get }
                }

                let value: UInt32
                init?(_ value: UInt32)
                init(_ value: UInt8)
                var properties: Unicode.Scalar.Properties { get }
                var description: String { get }

                var isASCII: Bool { value < 128 }
            }
        }

        struct Character: Hashable, Comparable, Sendable, CustomStringConvertible {
            init(_ text: String)
            init(_ scalar: Unicode.Scalar)
            var description: String { get }
            var isLetter: Bool { get }
            var isNumber: Bool { get }
            var isWholeNumber: Bool { get }
            var isWhitespace: Bool { get }
            var isPunctuation: Bool { get }
            var isUppercase: Bool { get }
            var isLowercase: Bool { get }
            var isASCII: Bool { get }
            var wholeNumberValue: Int? { get }
            var asciiValue: UInt8? { get }
            func uppercased() -> String
            func lowercased() -> String
        }

        struct Array<Element> {
            init()
            init<S: Sequence>(_ elements: S) where S.Element == Element
            init(repeating repeatedValue: Element, count: Int)
            var count: Int { get }
            var isEmpty: Bool { get }
            var startIndex: Int { get }
            var endIndex: Int { get }
            func index(after i: Int) -> Int
            func index(before i: Int) -> Int
            subscript(index: Int) -> Element { get set }
            /// The elements at the positions of a range, which reads as the array of them.
            subscript(bounds: [Int]) -> [Element] { get }
            mutating func append(_ newElement: Element)
            mutating func append(contentsOf newElements: [Element])
            mutating func insert(_ newElement: Element, at i: Int)
            mutating func remove(at index: Int) -> Element
            mutating func removeFirst() -> Element
            mutating func removeFirst(_ k: Int)
            mutating func removeLast() -> Element
            mutating func removeLast(_ k: Int)
            mutating func removeAll()
            mutating func removeAll(where shouldBeRemoved: (Element) throws -> Bool) rethrows
        }

        struct Dictionary<Key, Value> {
            init()
            var count: Int { get }
            var isEmpty: Bool { get }
            var keys: [Key] { get }
            var values: [Value] { get }
            subscript(key: Key) -> Value? { get set }
            subscript(key: Key, default defaultValue: Value) -> Value { get set }
            mutating func removeValue(forKey key: Key) -> Value?
            mutating func removeAll()
            func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> [Key: T]
            func filter(_ isIncluded: ((key: Key, value: Value)) throws -> Bool) rethrows -> [Key: Value]
            init<S: Sequence>(grouping values: S, by keyForValue: (S.Element) throws -> Key) rethrows where Value == [S.Element]
        }

        /// Unique elements, each once. Its index is an element's place among them.
        struct Set<Element: Hashable>: Hashable, Sendable, Codable {
            init()
            init<S: Sequence>(_ elements: S) where S.Element == Element
            var count: Int { get }
            var isEmpty: Bool { get }
            var startIndex: Int { get }
            var endIndex: Int { get }
            func index(after i: Int) -> Int
            subscript(position: Int) -> Element { get }
            func contains(_ member: Element) -> Bool
            @discardableResult mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element)
            @discardableResult mutating func remove(_ member: Element) -> Element?
            mutating func removeAll()
        }

        protocol ExpressibleByNilLiteral {
            init(nilLiteral: ())
        }

        enum Optional<Wrapped>: ExpressibleByNilLiteral {
            case none
            case some(Wrapped)
            init(_ some: Wrapped)
            init(nilLiteral: ())
            func map<U>(_ transform: (Wrapped) throws -> U) rethrows -> U?
            func flatMap<U>(_ transform: (Wrapped) throws -> U?) rethrows -> U?
        }

        enum Result<Success, Failure: Error> {
            case success(Success)
            case failure(Failure)

            func get() throws -> Success {
                switch self {
                case .success(let success): return success
                case .failure(let failure): throw failure
                }
            }

            func map<NewSuccess>(_ transform: (Success) throws -> NewSuccess) rethrows -> Result<NewSuccess, Failure> {
                switch self {
                case .success(let success): return .success(try transform(success))
                case .failure(let failure): return .failure(failure)
                }
            }

            func mapError<NewFailure: Error>(_ transform: (Failure) throws -> NewFailure) rethrows -> Result<Success, NewFailure> {
                switch self {
                case .success(let success): return .success(success)
                case .failure(let failure): return .failure(try transform(failure))
                }
            }

            func flatMap<NewSuccess>(_ transform: (Success) throws -> Result<NewSuccess, Failure>) rethrows -> Result<NewSuccess, Failure> {
                switch self {
                case .success(let success): return try transform(success)
                case .failure(let failure): return .failure(failure)
                }
            }
        }

        extension Result where Failure == any Error {
            init(catching body: () throws -> Success) {
                do {
                    self = .success(try body())
                } catch {
                    self = .failure(error)
                }
            }
        }

        struct Duration: Hashable, Comparable, Sendable {
            static func seconds(_ seconds: Int) -> Duration
            static func seconds(_ seconds: Double) -> Duration
            static func milliseconds(_ milliseconds: Int) -> Duration
        }

        struct Task: Sendable {
            init(operation: @escaping () async throws -> Void)
            func cancel()
            var isCancelled: Bool { get }
            static var isCancelled: Bool { get }
            static func sleep(for duration: Duration) async throws
            static func sleep(nanoseconds duration: Int) async throws
        }

        func print(_ items: Any..., separator: String = " ", terminator: String = "\\n")
        func min<T: Comparable>(_ x: T, _ y: T) -> T
        func max<T: Comparable>(_ x: T, _ y: T) -> T
        func abs<T: Comparable>(_ x: T) -> T
        func fatalError(_ message: String = "") -> Never
        """ + collections + fixedIntegers

    /// Swift's collection protocols, and what they give every type conforming to them, written in
    /// Swift once: each method runs for whichever collection it's used on, through the few
    /// members that collection has of its own.
    private static let collections = """

        protocol Sequence {
            associatedtype Element
        }

        protocol Collection: Sequence {
            associatedtype Index: Comparable
            associatedtype SubSequence
        }

        protocol BidirectionalCollection: Collection {}
        protocol RandomAccessCollection: BidirectionalCollection {}
        protocol MutableCollection: Collection {}
        protocol RangeReplaceableCollection: Collection {}

        /// The values from a lower bound up to, but not including, an upper one.
        struct Range<Bound: Comparable> {
            let lowerBound: Bound
            let upperBound: Bound

            var isEmpty: Bool { lowerBound == upperBound }

            func contains(_ element: Bound) -> Bool {
                lowerBound <= element && element < upperBound
            }
        }

        /// The values from a lower bound up to, and including, an upper one.
        struct ClosedRange<Bound: Comparable> {
            let lowerBound: Bound
            let upperBound: Bound

            func contains(_ element: Bound) -> Bool {
                lowerBound <= element && element <= upperBound
            }
        }

        /// What `String` and `Substring` are both: text, a collection of characters.
        protocol StringProtocol: BidirectionalCollection, RangeReplaceableCollection, Hashable, Comparable, CustomStringConvertible {}

        extension StringProtocol {
            var count: Int { get }
            var isEmpty: Bool { get }
            var startIndex: String.Index { get }
            var endIndex: String.Index { get }
            func index(after i: String.Index) -> String.Index
            func index(before i: String.Index) -> String.Index
            subscript(position: String.Index) -> Character { get }
            subscript(bounds: Range<String.Index>) -> Substring { get }
            @available(*, unavailable, message: "cannot subscript String with an Int, use a String.Index instead.")
            subscript(i: Int) -> Character { get }
            var description: String { get }
            /// Its UTF-8 code units: Swift's view of them, read as an array.
            var utf8: [UInt8] { get }
            /// Its Unicode scalars: Swift's view of them, read as an array.
            var unicodeScalars: [Unicode.Scalar] { get }
            func uppercased() -> String
            func lowercased() -> String
            func hasPrefix<T: StringProtocol>(_ prefix: T) -> Bool
            func hasSuffix<T: StringProtocol>(_ suffix: T) -> Bool
            func contains<T: StringProtocol>(_ other: T) -> Bool
        }

        extension String {
            typealias Element = Character
            typealias Index = String.Index
            typealias SubSequence = Substring
        }

        extension Substring {
            typealias Element = Character
            typealias Index = String.Index
            typealias SubSequence = Substring
        }

        extension Array: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
            typealias Index = Int
            typealias SubSequence = [Element]
        }

        extension Set: Collection {
            typealias Index = Int
            typealias SubSequence = [Element]
        }

        extension Set {
            func union<S: Sequence>(_ other: S) -> Set<Element> where S.Element == Element {
                var result = self
                for element in other {
                    result.insert(element)
                }
                return result
            }

            func intersection(_ other: Set<Element>) -> Set<Element> {
                var result = Set<Element>()
                for element in self {
                    if other.contains(element) {
                        result.insert(element)
                    }
                }
                return result
            }

            func subtracting(_ other: Set<Element>) -> Set<Element> {
                var result = Set<Element>()
                for element in self {
                    if !other.contains(element) {
                        result.insert(element)
                    }
                }
                return result
            }

            func symmetricDifference(_ other: Set<Element>) -> Set<Element> {
                subtracting(other).union(other.subtracting(self))
            }

            func isSubset(of other: Set<Element>) -> Bool {
                allSatisfy { other.contains($0) }
            }

            func isSuperset(of other: Set<Element>) -> Bool {
                other.isSubset(of: self)
            }

            func isDisjoint(with other: Set<Element>) -> Bool {
                !contains(where: { other.contains($0) })
            }

            func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Set<Element> {
                var result = Set<Element>()
                for element in self {
                    if try isIncluded(element) {
                        result.insert(element)
                    }
                }
                return result
            }

            mutating func formUnion<S: Sequence>(_ other: S) where S.Element == Element {
                for element in other {
                    insert(element)
                }
            }

            mutating func subtract(_ other: Set<Element>) {
                for element in other {
                    remove(element)
                }
            }

            mutating func formIntersection(_ other: Set<Element>) {
                self = intersection(other)
            }
        }

        /// Two sequences' elements in pairs, as long as the shorter: Swift's `Zip2Sequence`, read
        /// as the array of them.
        func zip<Sequence1: Sequence, Sequence2: Sequence>(_ sequence1: Sequence1, _ sequence2: Sequence2) -> [(Sequence1.Element, Sequence2.Element)] {
            let first = Array(sequence1)
            let second = Array(sequence2)
            var result: [(Sequence1.Element, Sequence2.Element)] = []
            var index = 0
            while index < first.count && index < second.count {
                result.append((first[index], second[index]))
                index += 1
            }
            return result
        }

        extension Dictionary: Sequence {
            typealias Element = (key: Key, value: Value)
        }

        extension Sequence {
            /// Swift's lazy view, read as the sequence itself: the same values, made as they're asked for.
            var lazy: Self { self }

            func map<T>(_ transform: (Element) throws -> T) rethrows -> [T] {
                var result: [T] = []
                for element in self {
                    result.append(try transform(element))
                }
                return result
            }

            func compactMap<T>(_ transform: (Element) throws -> T?) rethrows -> [T] {
                var result: [T] = []
                for element in self {
                    if let value = try transform(element) {
                        result.append(value)
                    }
                }
                return result
            }

            func flatMap<T>(_ transform: (Element) throws -> [T]) rethrows -> [T] {
                var result: [T] = []
                for element in self {
                    result.append(contentsOf: try transform(element))
                }
                return result
            }

            func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> [Element] {
                var result: [Element] = []
                for element in self {
                    if try isIncluded(element) {
                        result.append(element)
                    }
                }
                return result
            }

            func forEach(_ body: (Element) throws -> Void) rethrows {
                for element in self {
                    try body(element)
                }
            }

            func contains(where predicate: (Element) throws -> Bool) rethrows -> Bool {
                for element in self {
                    if try predicate(element) {
                        return true
                    }
                }
                return false
            }

            func allSatisfy(_ predicate: (Element) throws -> Bool) rethrows -> Bool {
                for element in self {
                    if try !predicate(element) {
                        return false
                    }
                }
                return true
            }

            func first(where predicate: (Element) throws -> Bool) rethrows -> Element? {
                for element in self {
                    if try predicate(element) {
                        return element
                    }
                }
                return nil
            }

            func reduce<Result>(into initialResult: Result, _ updateAccumulatingResult: (inout Result, Element) throws -> ()) rethrows -> Result {
                var result = initialResult
                for element in self {
                    try updateAccumulatingResult(&result, element)
                }
                return result
            }

            func reduce<Result>(_ initialResult: Result, _ nextPartialResult: (Result, Element) throws -> Result) rethrows -> Result {
                var result = initialResult
                for element in self {
                    result = try nextPartialResult(result, element)
                }
                return result
            }

            func enumerated() -> [(offset: Int, element: Element)] {
                var result: [(offset: Int, element: Element)] = []
                var offset = 0
                for element in self {
                    result.append((offset: offset, element: element))
                    offset += 1
                }
                return result
            }

            /// Sorted, the elements that are equal kept in the order they were in, as Swift's
            /// sort keeps them.
            func sorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> [Element] {
                var result: [Element] = []
                for element in self {
                    var position = result.count
                    while position > 0 {
                        let goesBefore = try areInIncreasingOrder(element, result[position - 1])
                        if !goesBefore {
                            break
                        }
                        position -= 1
                    }
                    result.insert(element, at: position)
                }
                return result
            }

            func min(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element? {
                var result: Element? = nil
                for element in self {
                    if let current = result {
                        if try areInIncreasingOrder(element, current) {
                            result = element
                        }
                    } else {
                        result = element
                    }
                }
                return result
            }

            func max(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Element? {
                var result: Element? = nil
                for element in self {
                    if let current = result {
                        if try areInIncreasingOrder(current, element) {
                            result = element
                        }
                    } else {
                        result = element
                    }
                }
                return result
            }
        }

        extension Sequence where Element: Equatable {
            func contains(_ element: Element) -> Bool {
                for candidate in self {
                    if candidate == element {
                        return true
                    }
                }
                return false
            }
        }

        extension Sequence where Element: Comparable {
            func sorted() -> [Element] {
                sorted(by: { $0 < $1 })
            }

            func min() -> Element? {
                min(by: { $0 < $1 })
            }

            func max() -> Element? {
                max(by: { $0 < $1 })
            }
        }

        extension Sequence where Element: StringProtocol {
            func joined(separator: String = "") -> String {
                var result = ""
                var isFirst = true
                for element in self {
                    if !isFirst {
                        result += separator
                    }
                    result += element
                    isFirst = false
                }
                return result
            }
        }

        extension Collection {
            var first: Element? {
                isEmpty ? nil : self[startIndex]
            }

            var indices: [Index] {
                var result: [Index] = []
                var position = startIndex
                while position != endIndex {
                    result.append(position)
                    position = index(after: position)
                }
                return result
            }

            func index(_ i: Index, offsetBy distance: Int) -> Index {
                var position = i
                var remaining = distance
                while remaining > 0 {
                    position = index(after: position)
                    remaining -= 1
                }
                return position
            }

            func distance(from start: Index, to end: Index) -> Int {
                var count = 0
                var position = start
                while position != end {
                    position = index(after: position)
                    count += 1
                }
                return count
            }

            func firstIndex(where predicate: (Element) throws -> Bool) rethrows -> Index? {
                var position = startIndex
                while position != endIndex {
                    if try predicate(self[position]) {
                        return position
                    }
                    position = index(after: position)
                }
                return nil
            }

            func prefix(_ maxLength: Int) -> SubSequence {
                if maxLength < 0 {
                    fatalError("Can't take a prefix of negative length from a collection")
                }
                let length = maxLength < count ? maxLength : count
                return self[startIndex..<index(startIndex, offsetBy: length)]
            }

            func suffix(_ maxLength: Int) -> SubSequence {
                if maxLength < 0 {
                    fatalError("Can't take a suffix of negative length from a collection")
                }
                let length = maxLength < count ? maxLength : count
                return self[index(startIndex, offsetBy: count - length)..<endIndex]
            }

            func dropFirst(_ k: Int = 1) -> SubSequence {
                if k < 0 {
                    fatalError("Can't drop a negative number of elements from a collection")
                }
                let length = k < count ? k : count
                return self[index(startIndex, offsetBy: length)..<endIndex]
            }

            func dropLast(_ k: Int = 1) -> SubSequence {
                if k < 0 {
                    fatalError("Can't drop a negative number of elements from a collection")
                }
                let length = k < count ? k : count
                return self[startIndex..<index(startIndex, offsetBy: count - length)]
            }

            func prefix(while predicate: (Element) throws -> Bool) rethrows -> SubSequence {
                var end = startIndex
                while end != endIndex {
                    if try !predicate(self[end]) {
                        break
                    }
                    end = index(after: end)
                }
                return self[startIndex..<end]
            }

            func drop(while predicate: (Element) throws -> Bool) rethrows -> SubSequence {
                var start = startIndex
                while start != endIndex {
                    if try !predicate(self[start]) {
                        break
                    }
                    start = index(after: start)
                }
                return self[start..<endIndex]
            }
        }

        extension Collection where Element: Equatable {
            func firstIndex(of element: Element) -> Index? {
                firstIndex(where: { $0 == element })
            }

            /// The parts between each `separator`, as Swift splits them.
            func split(separator: Element, maxSplits: Int = Int.max, omittingEmptySubsequences: Bool = true) -> [SubSequence] {
                var result: [SubSequence] = []
                if maxSplits == 0 {
                    if !omittingEmptySubsequences || !isEmpty {
                        result.append(self[startIndex..<endIndex])
                    }
                    return result
                }
                var start = startIndex
                var end = startIndex
                while end != endIndex {
                    if self[end] == separator {
                        let appended = !(start == end && omittingEmptySubsequences)
                        if appended {
                            result.append(self[start..<end])
                        }
                        end = index(after: end)
                        start = end
                        if appended && result.count == maxSplits {
                            break
                        }
                        continue
                    }
                    end = index(after: end)
                }
                if start != endIndex || !omittingEmptySubsequences {
                    result.append(self[start..<endIndex])
                }
                return result
            }
        }

        extension BidirectionalCollection {
            var last: Element? {
                isEmpty ? nil : self[index(before: endIndex)]
            }

            func index(_ i: Index, offsetBy distance: Int) -> Index {
                var position = i
                var remaining = distance
                while remaining > 0 {
                    position = index(after: position)
                    remaining -= 1
                }
                while remaining < 0 {
                    position = index(before: position)
                    remaining += 1
                }
                return position
            }

            func last(where predicate: (Element) throws -> Bool) rethrows -> Element? {
                var position = endIndex
                while position != startIndex {
                    position = index(before: position)
                    if try predicate(self[position]) {
                        return self[position]
                    }
                }
                return nil
            }

            func lastIndex(where predicate: (Element) throws -> Bool) rethrows -> Index? {
                var position = endIndex
                while position != startIndex {
                    position = index(before: position)
                    if try predicate(self[position]) {
                        return position
                    }
                }
                return nil
            }

            /// Its elements, last first: Swift's view of them, read as an array.
            func reversed() -> [Element] {
                var result: [Element] = []
                var position = endIndex
                while position != startIndex {
                    position = index(before: position)
                    result.append(self[position])
                }
                return result
            }
        }

        extension BidirectionalCollection where Element: Equatable {
            func lastIndex(of element: Element) -> Index? {
                lastIndex(where: { $0 == element })
            }
        }

        extension RangeReplaceableCollection {
            func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Self {
                var result = Self()
                for element in self {
                    if try isIncluded(element) {
                        result.append(element)
                    }
                }
                return result
            }

            mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Element {
                for element in newElements {
                    append(element)
                }
            }
        }
        """

    /// The integer types: each one `FixedWidthInteger`, which gives it all it has.
    private static var fixedIntegers: String {
        FixedInteger.allCases.map { "\nstruct \($0.rawValue): Sendable, Codable, FixedWidthInteger {}" }.joined()
            + integers
    }

    /// What every integer type has, as Swift's `BinaryInteger` and `FixedWidthInteger` give it,
    /// once: the interpreter runs each, as the type it's used on.
    private static let integers = """

        extension BinaryInteger {
            init<T: BinaryInteger>(_ source: T)
            init<T: BinaryInteger>(truncatingIfNeeded source: T)
            init?<T: BinaryInteger>(exactly source: T)
            init(_ value: Double)
            var description: String { get }
            func isMultiple(of other: Self) -> Bool
        }

        extension FixedWidthInteger {
            init?(_ text: String)
            static var max: Self { get }
            static var min: Self { get }
            static var bitWidth: Int { get }
        }
        """
}
