import Doppel
import Synchronization

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
    /// An `AsyncStream` or `AsyncThrowingStream`, its continuation, or an iterator over it.
    case stream(StreamBox)
    case continuation(StreamBox)
    case streamIterator(StreamIterator)
    /// A type, as a value: `Int.self`.
    case metatype(SwiftType)
    /// Foundation's value types, run with the process's own Foundation.
    case date(Date)
    case decimal(Decimal)
    case uuid(UUID)
    case url(URL)
    case data(Data)
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

/// A stream the code made, as Swift's `AsyncStream` is: what's yielded is kept, in order, until
/// whoever loops over it asks; asked when there's nothing yet, it waits for the next yield or for
/// the stream to finish. Once finished, it gives what's left, then its error once, if it ended with
/// one, then nothing. The task looping over it being cancelled finishes it, as Swift's does.
///
/// Its code yields and waits in the one place all its code runs, at its `await`s, so values never
/// cross to another: a waiting `next()` is only woken, and reads the value itself. Only its task's
/// cancellation wakes it from elsewhere.
package final class StreamBox {
    /// How many values a stream keeps for whoever loops over it, and which it drops past that, as
    /// Swift's `BufferingPolicy` says.
    enum Limit {
        case unbounded
        case oldest(Int)
        case newest(Int)
    }

    /// What became of a value yielded, as Swift's `YieldResult` says.
    enum Yielded {
        case enqueued(remaining: Int)
        case dropped(Value)
        case terminated
    }

    /// Why a stream ended, as Swift's `Termination` says: finished, with the error it was finished
    /// with, or its looping task cancelled.
    enum Ended {
        case finished(Value?)
        case cancelled
    }

    /// `AsyncStream` or `AsyncThrowingStream`: what its `Termination` is named in.
    let kind: String
    private let limit: Limit
    private var buffered: [Value] = []
    private var finished = false
    private var failure: Thrown?
    private let waiting = Waiting()
    /// What's called once when it ends, as its continuation's `onTermination` was set.
    var onTermination: Value?
    /// Why it ended, until its handler's been called for it.
    private var ended: Ended?

    init(kind: String = "AsyncStream", limit: Limit = .unbounded) {
        self.kind = kind
        self.limit = limit
    }

    /// Why it ended, the once: its handler is called for it, then it's gone.
    func takeEnded() -> Ended? {
        defer { ended = nil }
        return ended
    }

    /// Keeps `value` for whoever asks next, as the stream's limit lets it: one waiting takes it
    /// whatever the limit; past the limit, the newest or the oldest is dropped.
    func yield(_ value: Value) -> Yielded {
        guard !finished else { return .terminated }
        let room: Int
        switch limit {
        case .unbounded: room = .max
        case .oldest(let count), .newest(let count): room = count
        }
        if waiting.isWaiting {
            buffered.append(value)
            wake()
            return .enqueued(remaining: room)
        }
        switch limit {
        case .unbounded:
            buffered.append(value)
            return .enqueued(remaining: .max)
        case .oldest(let count):
            guard buffered.count < count else { return .dropped(value) }
            buffered.append(value)
            return .enqueued(remaining: count - buffered.count)
        case .newest(let count):
            guard count > 0 else { return .dropped(value) }
            if buffered.count >= count {
                let dropped = buffered.removeFirst()
                buffered.append(value)
                return .dropped(dropped)
            }
            buffered.append(value)
            return .enqueued(remaining: count - buffered.count)
        }
    }

    /// Finishes the stream, with `failure` thrown to whoever asks after what's left, when given:
    /// `error` is the value the code finished it with.
    func finish(throwing failure: Thrown? = nil, error: Value? = nil) {
        end(failure: failure, as: .finished(error))
    }

    private func end(failure: Thrown?, as reason: Ended) {
        guard !finished else { return }
        finished = true
        self.failure = failure
        ended = reason
        wake()
    }

    /// The next value, waited for; `nil` once it's finished and nothing's left. A cancelled task
    /// asking finishes it: it's given what's left, then nothing.
    func next() async throws -> Value? {
        while true {
            if !buffered.isEmpty { return buffered.removeFirst() }
            if finished {
                if let failure {
                    self.failure = nil
                    throw failure
                }
                return nil
            }
            if Task.isCancelled {
                end(failure: nil, as: .cancelled)
                continue
            }
            await waiting.wait()
        }
    }

    private func wake() {
        waiting.wake()
    }
}

/// The one `next()` waiting on a stream, woken by a yield or a finish where the stream's code runs,
/// or by its task being cancelled, from wherever that happens: so it's kept behind a lock, and only
/// the waking crosses.
private final class Waiting: Sendable {
    private let continuation = Mutex<CheckedContinuation<Void, Never>?>(nil)

    /// Waits to be woken, or for its task to be cancelled.
    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation.withLock { $0 = continuation }
                // Cancelled before it waited: its handler found nothing to wake.
                if Task.isCancelled { wake() }
            }
        } onCancel: {
            wake()
        }
    }

    func wake() {
        continuation.withLock { $0.take() }?.resume()
    }

    /// Whether a `next()` is waiting now.
    var isWaiting: Bool {
        continuation.withLock { $0 != nil }
    }
}

/// An iterator over a stream: each `next()` waits for the stream's next value.
package final class StreamIterator {
    let box: StreamBox

    init(_ box: StreamBox) {
        self.box = box
    }
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
