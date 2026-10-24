enum Stop: Error {
    case at(Int)
}

/// Counts down from a number to one, each waited for.
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

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(current: from)
    }
}

/// Counts up, and fails at a number.
struct Failing: AsyncSequence {
    let failingAt: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        let failingAt: Int
        var count = 0

        mutating func next() async throws -> Int? {
            count += 1
            if count == failingAt { throw Stop.at(count) }
            return count
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(failingAt: failingAt)
    }
}

/// Pairs of a number and its square.
struct Squares: AsyncSequence {
    let count: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        let count: Int
        var index = 0

        mutating func next() async -> (Int, Int)? {
            guard index < count else { return nil }
            index += 1
            return (index, index * index)
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(count: count)
    }
}

actor Program {
    let countdown = Countdown(from: 3)

    func sum(of sequence: Countdown) async -> Int {
        var total = 0
        for await number in sequence {
            total += number
        }
        return total
    }

    func run() async {
        for await number in Countdown(from: 3) {
            print("count", number)
        }
        print("sum", await sum(of: Countdown(from: 4)))
        for await number in countdown where number != 2 {
            print("not two", number)
        }
        for await number in Countdown(from: 10) {
            if number == 8 { continue }
            if number < 7 { break }
            print("high", number)
        }
        for await (number, square) in Squares(count: 3) {
            print(number, "squared is", square)
        }
        do {
            for try await number in Failing(failingAt: 3) {
                print("before failing", number)
            }
            print("not reached")
        } catch {
            print("failed", error)
        }
        for await _ in Countdown(from: 0) {
            print("never")
        }
        print("done")
    }
}
