actor Streamer {
    func watch() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        continuation.onTermination = { (count: Int) in print(count) }
        continuation.finish()
        for await _ in stream {}
    }
}
