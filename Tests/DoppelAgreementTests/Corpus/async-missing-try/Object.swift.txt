struct Countdown: AsyncSequence {
    typealias Element = Int
    let from: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        var current: Int

        mutating func next() async -> Int? {
            guard current > 0 else { return nil }
            defer { current -= 1 }
            return current
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(current: from) }
}

struct Failing: AsyncSequence {
    struct AsyncIterator: AsyncIteratorProtocol {
        mutating func next() async throws -> Int? { nil }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
}

actor Looper {
    func total() async throws -> Int {
        var sum = 0
        for await number in Failing() { sum += number }
        return sum
    }
}
