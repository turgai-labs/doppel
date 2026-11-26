struct Track {
    let title: String
    let artist: String
    let seconds: Int
}

actor Program {
    func run() {
        let tracks = [
            Track(title: "Tender", artist: "Blur", seconds: 467),
            Track(title: "Song 2", artist: "Blur", seconds: 122),
            Track(title: "Wonderwall", artist: "Oasis", seconds: 258),
            Track(title: "Live Forever", artist: "Oasis", seconds: 276),
            Track(title: "Pelican", artist: "The Maccabees", seconds: 205),
        ]
        let minutes = tracks.map { $0.seconds }.filter { $0 > 200 }.reduce(0, +) / 60
        print(minutes)
        let byArtist = tracks.reduce(into: [String: [String]]()) { result, track in
            result[track.artist, default: []].append(track.title)
        }
        print(byArtist.keys.sorted(), byArtist["Oasis"] ?? [])
        let words = tracks.flatMap { $0.title.split(separator: " ") }.map { $0.lowercased() }
        print(words, words.count)
        let initials = tracks.compactMap { $0.title.first }.map(String.init).joined()
        print(initials)
        let longest =
            tracks.max { $0.seconds < $1.seconds }.map { "\($0.title) \($0.seconds / 60):\($0.seconds % 60)" } ?? "none"
        print(longest)
        let summary =
            tracks
            .sorted { ($0.artist, $0.seconds) < ($1.artist, $1.seconds) }
            .enumerated()
            .map { "\($0.offset + 1). \($0.element.artist) – \($0.element.title)" }
            .prefix(3)
            .joined(separator: "\n")
        print(summary)
        let total = tracks.lazy.filter { $0.artist == "Blur" }.map(\.seconds).reduce(0, +)
        print(total, tracks.allSatisfy { $0.seconds > 100 }, tracks.contains { $0.title.hasPrefix("Song") })
        let lengths = Dictionary(grouping: tracks, by: { $0.artist }).mapValues { $0.count }
        print(lengths.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })
        let squares = (1...5).map { $0 * $0 }.filter { $0.isMultiple(of: 2) == false }
        print(squares, zip(squares, squares.dropFirst()).map { $1 - $0 })
    }
}
