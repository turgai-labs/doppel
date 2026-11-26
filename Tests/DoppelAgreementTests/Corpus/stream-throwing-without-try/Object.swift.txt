actor Streamer {
    func numbers() async throws {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Int.self)
        continuation.finish()
        for await number in stream { _ = number }
    }
}
