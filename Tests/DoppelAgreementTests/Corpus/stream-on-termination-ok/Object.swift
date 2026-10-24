actor Streamer {
    func watch() async {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
        continuation.onTermination = { termination in
            switch termination {
            case .finished: print("finished")
            case .cancelled: print("cancelled")
            @unknown default: print("ended")
            }
        }
        continuation.finish()
        for await _ in stream {}
    }
}
