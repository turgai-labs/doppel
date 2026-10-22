import Doppel

#if canImport(FoundationEssentials)
    import FoundationEssentials
#else
    import Foundation
#endif

/// A value, as the code running holds it: Swift's own kinds, its structs and enums, its actor, and
/// other objects, which the host holds. It stays with the code that runs it, on its executor; what
/// crosses to the host is `Portable`.
package indirect enum Value {
    case int(Int)
    case double(Double)
    case bool(Bool)
    case string(String)
    case character(Character)
    /// A fixed-width integer other than `Int`, as its bits.
    case fixed(FixedInteger, UInt64)
    case void
    case optional(Value?)
    case array([Value])
    /// A set's elements, each once, in the order they were first added.
    case set([Value])
    /// A dictionary's pairs, in the order they were added.
    case dictionary([(key: Value, value: Value)])
    case tuple([Value])
    case structure(String, [Value])
    case enumCase(String, String, [Value])
    /// The actor whose code this is.
    case actor(ActorInstance)
    /// Another object, as the host refers to it.
    case object(ObjectHandle)
    case function(FunctionValue)
    case duration(Duration)
    case task(TaskHandle)
    /// Foundation's value types, run with the process's own Foundation.
    case date(Date)
    case decimal(Decimal)
    case uuid(UUID)
    case url(URL)
}

/// Another object: what the host knows it by, and the actor type it is when that's known.
/// Doppel never looks inside the reference. Two handles are the same object when their
/// references are, whether or not each knows its type.
public struct ObjectHandle: Sendable, Hashable {
    public let reference: String
    /// The actor type it's of, when whoever gave it knew: what it's checked against where code
    /// takes an object of a type.
    public let type: String?

    public init(_ reference: String, type: String? = nil) {
        self.reference = reference
        self.type = type
    }

    public static func == (lhs: ObjectHandle, rhs: ObjectHandle) -> Bool { lhs.reference == rhs.reference }
    public func hash(into hasher: inout Hasher) { hasher.combine(reference) }
}

/// A `Task` the code started: the host runs it by its number.
package struct TaskHandle: Sendable {
    let id: Int
}

/// The actor running: its stored properties, by index, and its type. Its code runs one call at a
/// time on whoever runs it, so its fields are changed only there.
package final class ActorInstance {
    let type: String
    var fields: [Value]

    init(type: String, fields: [Value]) {
        self.type = type
        self.fields = fields
    }
}

/// A closure, with the frame it was made in.
package final class FunctionValue {
    let closure: Closure
    let frame: Frame

    init(closure: Closure, frame: Frame) {
        self.closure = closure
        self.frame = frame
    }
}

/// A function's locals while it runs, `self`, and the frame it was made in, for a closure.
package final class Frame {
    var slots: [Value]
    let parent: Frame?
    /// `self`, for a method: a struct's is its value, which a mutating method changes here.
    var selfValue: Value?

    init(slots: Int, parent: Frame?, selfValue: Value?) {
        self.slots = Array(repeating: .void, count: slots)
        self.parent = parent
        self.selfValue = selfValue ?? parent?.selfValue
    }

    func frame(_ depth: Int) -> Frame {
        var frame = self
        for _ in 0..<depth { frame = frame.parent! }
        return frame
    }

    /// The frame `self` is held in: the method's, which its closures share.
    var selfFrame: Frame {
        var frame = self
        while frame.parent != nil, frame.parent?.selfValue != nil { frame = frame.parent! }
        return frame
    }
}

/// What the code threw: a value of a type conforming to `Error`, as it crosses to whoever gets it.
public struct Thrown: Error, Sendable, CustomStringConvertible {
    public let type: String
    public let value: Portable
    /// Which value it was, to whoever catches it in the same code.
    let id: Int

    public var description: String { "\(type): \(value)" }
}

/// What stops the code where Swift would stop it: an index out of range, a `nil` force-unwrapped,
/// `fatalError`. It isn't caught by `try?`.
public struct Trap: Error, Sendable, CustomStringConvertible {
    public let message: String
    /// The line of the file it stopped at, once it's known.
    public let line: Int?

    public init(message: String, line: Int? = nil) {
        self.message = message
        self.line = line
    }

    public var description: String { line.map { "line \($0): \(message)" } ?? message }
}

/// Where a part of a value is in it, as Swift writes the path to it: `items[2].amount`.
public struct ValuePath: Sendable, Equatable, CustomStringConvertible {
    /// A step into a value: a struct's field or an enum case's value, an element, or a
    /// dictionary's key.
    public enum Step: Sendable, Equatable {
        case member(String)
        case index(Int)
        case key(String)
    }

    public private(set) var steps: [Step]

    public init(_ steps: [Step] = []) {
        self.steps = steps
    }

    /// The path to the value named `name`: a parameter's, or a field's.
    public init(named name: String) {
        self.init([.member(name)])
    }

    func appending(_ step: Step) -> ValuePath {
        ValuePath(steps + [step])
    }

    public var description: String {
        steps.enumerated().map { index, step in
            switch step {
            case .member(let name): index == 0 ? name : ".\(name)"
            case .index(let index): "[\(index)]"
            case .key(let key): "[\"\(key)\"]"
            }
        }.joined()
    }

    /// What isn't of its type here, said with where it is: "`items[2].amount`: …".
    func mismatch(_ reason: String) -> Trap {
        Trap(message: steps.isEmpty ? reason : "`\(self)`: \(reason)")
    }
}

/// A value as it crosses to the host and back: as `Codable` writes it, as JSON has it.
public enum Portable: Sendable, Equatable, CustomStringConvertible {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Portable])
    /// An object's members, in order.
    case object([(String, Portable)])
    /// Another object, by what the host refers to it as.
    case reference(ObjectHandle)

    public static func == (lhs: Portable, rhs: Portable) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let a), .bool(let b)): a == b
        case (.int(let a), .int(let b)): a == b
        case (.double(let a), .double(let b)): a == b
        case (.int(let a), .double(let b)), (.double(let b), .int(let a)): Double(a) == b
        case (.string(let a), .string(let b)): a == b
        case (.array(let a), .array(let b)): a == b
        case (.object(let a), .object(let b)):
            a.count == b.count && a.allSatisfy { member in b.contains { $0.0 == member.0 && $0.1 == member.1 } }
        case (.reference(let a), .reference(let b)): a == b
        default: false
        }
    }

    public subscript(member: String) -> Portable? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.0 == member }?.1
    }

    public var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .int(let value): "\(value)"
        case .double(let value): "\(value)"
        case .string(let value): "\"\(value)\""
        case .array(let values): "[\(values.map(\.description).joined(separator: ", "))]"
        case .object(let members): "{\(members.map { "\"\($0.0)\": \($0.1)" }.joined(separator: ", "))}"
        case .reference(let handle): "<\(handle.reference)>"
        }
    }
}
