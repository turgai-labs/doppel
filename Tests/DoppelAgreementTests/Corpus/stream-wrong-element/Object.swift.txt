actor Streamer {
    func numbers() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        continuation.yield("tea")
        continuation.finish()
        for await number in stream { _ = number }
    }
}
