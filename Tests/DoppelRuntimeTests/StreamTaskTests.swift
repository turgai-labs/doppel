import Doppel
import Testing

@testable import DoppelRuntime

/// A `Task` the code starts runs on the object's executor, as its host runs it: while a loop over a
/// stream waits, the task yields to it, and the loop takes each value as it comes, as in Swift.
@Suite("Streams fed by tasks")
struct StreamTaskTests {
    static let program = """
        actor Program {
            var continuation: AsyncStream<Int>.Continuation?

            func produce() async {
                for value in 1...3 {
                    continuation?.yield(value * 10)
                    try? await Task.sleep(for: .milliseconds(10))
                }
                continuation?.finish()
            }

            func run() async {
                let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
                self.continuation = continuation
                Task { await self.produce() }
                for await value in stream {
                    print("got", value)
                }
                print("done")
            }
        }
        """

    @Test(.timeLimit(.minutes(1)))
    func aTaskYieldsToAWaitingLoop() async throws {
        let object = try await TaskRunner(code: Self.program)
        try await object.run()
        // As Swift's build of it prints.
        #expect(await object.printed == "got 10\ngot 20\ngot 30\ndone\n")
    }

    static let cancelled = """
        actor Program {
            var stream: AsyncStream<Int>?
            var continuation: AsyncStream<Int>.Continuation?

            func consume() async {
                guard let stream else { return }
                for await value in stream {
                    print("got", value)
                }
                print("loop ended")
            }

            func run() async {
                let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
                self.stream = stream
                self.continuation = continuation
                continuation.yield(1)
                let consumer = Task { await self.consume() }
                try? await Task.sleep(for: .milliseconds(50))
                consumer.cancel()
                try? await Task.sleep(for: .milliseconds(50))
                print("after cancel:", continuation.yield(2))
            }
        }
        """

    /// A loop waiting on a stream ends when its task is cancelled, and the stream with it: a yield
    /// after is dropped, as Swift's terminated says.
    @Test(.timeLimit(.minutes(1)))
    func cancellingTheWaitingTaskEndsTheStream() async throws {
        let object = try await TaskRunner(code: Self.cancelled)
        try await object.run()
        // As Swift's build of it prints.
        #expect(await object.printed == "got 1\nloop ended\nafter cancel: terminated\n")
    }
    static let buffering = """
        actor Program {
            var waitingContinuation: AsyncStream<Int>.Continuation?

            func drain(_ stream: AsyncStream<Int>) async -> [Int] {
                var seen: [Int] = []
                for await value in stream { seen.append(value) }
                return seen
            }

            func fillWhileWaiting() async {
                try? await Task.sleep(for: .milliseconds(30))
                print("to a waiting loop:", waitingContinuation!.yield(9))
                waitingContinuation!.finish()
            }

            func run() async {
                let (oldest, oldestContinuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingOldest(2))
                for value in 1...4 { print("oldest", value, oldestContinuation.yield(value)) }
                oldestContinuation.finish()
                print("oldest kept", await drain(oldest))

                let (newest, newestContinuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(2))
                for value in 1...4 { print("newest", value, newestContinuation.yield(value)) }
                newestContinuation.finish()
                print("newest kept", await drain(newest))

                let (none, noneContinuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(0))
                print("none", noneContinuation.yield(1))
                noneContinuation.finish()
                print("none kept", await drain(none))

                let (unbounded, unboundedContinuation) = AsyncStream.makeStream(of: Int.self)
                print("unbounded", unboundedContinuation.yield(1))
                unboundedContinuation.finish()
                print("unbounded kept", await drain(unbounded))

                let built = AsyncStream(Int.self, bufferingPolicy: .bufferingOldest(1)) { continuation in
                    print("built", continuation.yield(1), continuation.yield(2))
                    continuation.finish()
                }
                print("built kept", await drain(built))

                let (waiting, waitingContinuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingOldest(0))
                self.waitingContinuation = waitingContinuation
                Task { await self.fillWhileWaiting() }
                print("waiting kept", await drain(waiting))

                let (throwing, throwingContinuation) = AsyncThrowingStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(1))
                print("throwing", throwingContinuation.yield(1), throwingContinuation.yield(2))
                throwingContinuation.finish()
                var kept: [Int] = []
                do { for try await value in throwing { kept.append(value) } } catch {}
                print("throwing kept", kept)
            }
        }
        """

    /// A stream keeps as many values as its buffering policy says, dropping the oldest or the
    /// newest past that, and gives one to a loop already waiting whatever its limit, as Swift's does.
    @Test(.timeLimit(.minutes(1)))
    func aStreamKeepsWhatItsPolicySays() async throws {
        let object = try await TaskRunner(code: Self.buffering)
        try await object.run()
        // As Swift's build of it prints.
        let expected = """
            oldest 1 enqueued(remaining: 1)
            oldest 2 enqueued(remaining: 0)
            oldest 3 dropped(3)
            oldest 4 dropped(4)
            oldest kept [1, 2]
            newest 1 enqueued(remaining: 1)
            newest 2 enqueued(remaining: 0)
            newest 3 dropped(1)
            newest 4 dropped(2)
            newest kept [3, 4]
            none dropped(1)
            none kept []
            unbounded enqueued(remaining: 9223372036854775807)
            unbounded kept [1]
            built enqueued(remaining: 0) dropped(2)
            built kept [1]
            to a waiting loop: enqueued(remaining: 0)
            waiting kept [9]
            throwing enqueued(remaining: 0) dropped(1)
            throwing kept [2]

            """
        let printed = await object.printed
        for (line, (ours, swift)) in zip(printed.split(separator: "\n"), expected.split(separator: "\n")).enumerated()
        where ours != swift {
            Issue.record("line \(line + 1): Swift printed `\(swift)`, Doppel `\(ours)`")
        }
        #expect(printed == expected)
    }
    static let termination = """
        enum Late: Error {
            case gone
        }

        actor Program {
            var stream: AsyncStream<Int>?

            func consume() async {
                guard let stream else { return }
                for await _ in stream {}
            }

            func run() async {
                let (finished, finishedContinuation) = AsyncStream.makeStream(of: Int.self)
                finishedContinuation.onTermination = { termination in print("finished:", termination) }
                finishedContinuation.yield(1)
                finishedContinuation.finish()
                finishedContinuation.finish()
                for await _ in finished {}
                print("after finish")

                let (cancelled, cancelledContinuation) = AsyncStream.makeStream(of: Int.self)
                cancelledContinuation.onTermination = { termination in print("cancelled:", termination) }
                stream = cancelled
                let consumer = Task { await self.consume() }
                try? await Task.sleep(for: .milliseconds(50))
                consumer.cancel()
                try? await Task.sleep(for: .milliseconds(50))
                print("after cancel")

                let (throwing, throwingContinuation) = AsyncThrowingStream.makeStream(of: Int.self)
                throwingContinuation.onTermination = { termination in
                    switch termination {
                    case .finished(let error): print("throwing finished, with an error:", error != nil)
                    case .cancelled: print("throwing cancelled")
                    @unknown default: print("throwing ended")
                    }
                }
                throwingContinuation.finish(throwing: Late.gone)
                do {
                    for try await _ in throwing {}
                } catch {
                    print("caught", error)
                }

                let (plain, plainContinuation) = AsyncThrowingStream.makeStream(of: Int.self)
                plainContinuation.onTermination = { termination in
                    switch termination {
                    case .finished(let error): print("plain finished, with an error:", error != nil)
                    case .cancelled: print("plain cancelled")
                    @unknown default: print("plain ended")
                    }
                }
                plainContinuation.finish()
                print("handler after:", plainContinuation.onTermination == nil)
                print("done")
            }
        }
        """

    /// A stream's onTermination is called once, when it ends: finished, with its error if it was
    /// finished with one, or its looping task cancelled; then it's let go, as Swift lets go of it.
    @Test(.timeLimit(.minutes(1)))
    func aStreamSaysOnceWhyItEnded() async throws {
        let object = try await TaskRunner(code: Self.termination)
        try await object.run()
        // As Swift's build of it prints.
        let expected = """
            finished: finished
            after finish
            cancelled: cancelled
            after cancel
            throwing finished, with an error: true
            caught gone
            plain finished, with an error: false
            handler after: true
            done

            """
        let printed = await object.printed
        for (line, (ours, swift)) in zip(printed.split(separator: "\n"), expected.split(separator: "\n")).enumerated()
        where ours != swift {
            Issue.record("line \(line + 1): Swift printed `\(swift)`, Doppel `\(ours)`")
        }
        #expect(printed == expected)
    }
}

/// The object, run on an actor of its own, as a host runs it: its tasks run there too.
private actor TaskRunner {
    private let host = TaskHost()
    private var live: LiveActor?

    init(code: String) async throws {
        live = try await LiveActor(
            type: "Program", in: "Program.swift", of: [.init(name: "Program.swift", code: code)],
            module: "program", host: host)
        host.runner = self
    }

    var printed: String { host.printed }

    func run() async throws { _ = try await live?.call("run", arguments: []) }

    func runTask(_ id: Int) async throws { try await live?.runTask(id) }
}

/// A host that runs each task the code starts on the object's actor, and keeps what it printed.
private final class TaskHost: ActorHost {
    weak var runner: TaskRunner?
    let itself = ObjectHandle("itself")
    var printed = ""

    func send(
        _ message: String, to object: ObjectHandle, through type: String?,
        arguments: [(label: String?, value: Portable)]
    ) async throws -> Portable { .null }
    func read(_ property: String, of object: ObjectHandle) async throws -> Portable { .null }
    func make(_ type: String, arguments: [(label: String?, value: Portable)]) async throws -> ObjectHandle {
        ObjectHandle(type)
    }
    func call(_ function: String, arguments: [(label: String?, value: Portable)]) async throws -> Portable { .null }
    /// The tasks it runs, by number, as the code knows them: to cancel one when the code does.
    private var running: [Int: Task<Void, any Error>] = [:]

    func schedule(task id: Int) {
        guard let runner else { return }
        running[id] = Task { try await runner.runTask(id) }
    }
    func cancel(task id: Int) { running.removeValue(forKey: id)?.cancel() }
    func print(_ text: String) { printed += text }
}
