enum Late: Error {
    case gone
}

actor Program {
    var continuation: AsyncStream<Int>.Continuation?

    func keep(_ values: [Int]) {
        for value in values { continuation?.yield(value) }
        continuation?.finish()
    }

    func run() async {
        let numbers = AsyncStream<Int> { continuation in
            for number in 1...3 { continuation.yield(number) }
            continuation.finish()
        }
        for await number in numbers {
            print("built", number)
        }

        let (words, wordsContinuation) = AsyncStream.makeStream(of: String.self)
        wordsContinuation.yield("tea")
        wordsContinuation.yield("coffee")
        wordsContinuation.finish()
        wordsContinuation.yield("after")
        var heard: [String] = []
        for await word in words {
            heard.append(word)
        }
        print(heard)

        let (counts, countsContinuation) = AsyncStream.makeStream(of: Int.self)
        print(countsContinuation.yield(1))
        countsContinuation.finish()
        print(countsContinuation.yield(2))
        for await count in counts {
            print("count", count)
        }

        let (failing, failingContinuation) = AsyncThrowingStream.makeStream(of: Int.self)
        failingContinuation.yield(7)
        failingContinuation.finish(throwing: Late.gone)
        do {
            for try await value in failing {
                print("value", value)
            }
            print("not reached")
        } catch {
            print("caught", error)
        }

        let (kept, keptContinuation) = AsyncStream.makeStream(of: Int.self)
        continuation = keptContinuation
        keep([10, 20])
        for await value in kept {
            print("kept", value)
        }
    }
}
