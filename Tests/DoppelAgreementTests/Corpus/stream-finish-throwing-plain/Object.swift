actor Streamer {
    func numbers() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        continuation.finish(throwing: nil)
        for await number in stream { _ = number }
    }
}
