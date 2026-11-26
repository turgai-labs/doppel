actor History {
    var tracks: [String] = []
    var counts: [String: Int] = [:]

    func add(_ track: String) {
        tracks.insert(track, at: 0)
        if tracks.count > 5 {
            tracks.removeLast(tracks.count - 5)
        }
        counts[track, default: 0] += 1
    }

    func summary() -> String {
        let top = counts.keys.sorted().prefix(3)
        var lines: [String] = []
        for (index, track) in tracks.enumerated() where !track.isEmpty {
            lines.append("\(index + 1). \(track)")
        }
        for (track, count) in counts {
            lines.append("\(track): \(count)")
        }
        let total = counts.values.reduce(0, +)
        return lines.joined(separator: "\n") + "\(top.count) \(total)"
    }

    func first() -> String? {
        tracks.first(where: { $0.hasPrefix("A") }) ?? tracks.first
    }
}
