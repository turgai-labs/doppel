actor Program {
    var history: [String] = []
    var counts: [String: Int] = [:]

    func run() async {
        for track in ["a", "b", "c", "a", "d", "e", "f", "g"] {
            history.insert(track, at: 0)
            if history.count > 5 {
                history.removeLast(history.count - 5)
            }
            counts[track, default: 0] += 1
        }
        print(history)
        print(counts.keys.sorted(), counts["a"] ?? 0, counts["z"] as Any)
        counts["a"] = nil
        print(counts.count, counts.values.reduce(0, +))
        let numbers = [5, 3, 8, 1]
        print(numbers.sorted(), numbers.sorted(by: >), numbers.map { $0 * 2 }, numbers.filter { $0 > 3 })
        print(numbers.reduce(0) { $0 + $1 }, numbers.min() ?? 0, numbers.max() ?? 0, numbers.contains(8), numbers.firstIndex(of: 8) ?? -1)
        // `reversed()` is a view in Swift, which prints as its internals; Doppel's is the
        // array it reads as.
        print(numbers.prefix(2), numbers.dropFirst(), Array(numbers.reversed()), numbers.first(where: { $0 < 4 }) ?? 0)
        for (index, number) in numbers.enumerated() where index % 2 == 0 {
            print(index, number)
        }
        var words = ["x", "y"]
        words.append(contentsOf: ["z"])
        words.removeFirst(1)
        words.append("w")
        let removed = words.removeFirst()
        print(removed, words.joined(separator: "-"), words.isEmpty, words.last ?? "")
        print(Array(0..<3), (1...3).map { $0 * $0 })
        let nested = [[1, 2], [3]]
        print(nested.flatMap { $0 }, nested.compactMap { $0.first })
    }
}
