actor Streamer {
    var continuation: AsyncStream<Int>.Continuation?

    func numbers() async -> [Int] {
        let stream = AsyncStream<Int> { continuation in
            continuation.yield(1)
            continuation.finish()
        }
        var seen: [Int] = []
        for await number in stream { seen.append(number) }
        let (words, wordsContinuation) = AsyncStream.makeStream(of: String.self)
        wordsContinuation.yield("tea")
        wordsContinuation.finish()
        for await word in words { seen.append(word.count) }
        return seen
    }

    func failing() async throws -> Int {
        let (values, continuation) = AsyncThrowingStream.makeStream(of: Int.self)
        continuation.finish(throwing: nil)
        var total = 0
        for try await value in values { total += value }
        return total
    }
}
