protocol Describing {
    var name: String { get }
}

extension Describing {
    func greeting(_ times: Int) -> String {
        String(repeating: "hi ", count: times) + name
    }
}

struct Person: Describing {
    let name: String
}

actor Program {
    func slug(_ parts: String...) -> String {
        var out = ""
        var lastWasDash = false
        for ch in parts.joined(separator: " ").lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") {
            out.removeLast()
        }
        while out.hasPrefix("-") {
            out.removeFirst()
        }
        return out
    }

    func run() {
        print(slug("Blur", "13 (Special Edition)", "Tender"))
        let title = "Champagne Supernova"
        print(String(title.prefix(9)), String(title.suffix(4)), String(title.dropFirst(10)), String(title.dropLast(5)))
        let end = title.index(title.startIndex, offsetBy: 5)
        print(title[title.startIndex..<end], title[end], title.distance(from: title.startIndex, to: end))
        print(title.first ?? "?", title.last ?? "?", title.firstIndex(of: "S") != nil, title.filter { $0 != "a" })
        let letters = Array(title.prefix(4))
        print(
            letters, Array(letters.reversed()), letters[1..<3], letters.firstIndex(of: "m") ?? -1,
            letters.lastIndex(of: "a") ?? -1)
        print(title.prefix(while: { $0 != " " }), title.drop(while: { $0 != " " }), title.indices.count)
        for (offset, ch) in "abc".enumerated() {
            print(offset, ch, terminator: " ")
        }
        print()
        var words = ["one"]
        words.append(contentsOf: ["two", "three"])
        print(
            words.map { $0.count }, words.sorted(), words.min() ?? "", words.contains("two"),
            words.dropFirst().joined(separator: "+"))
        print(Person(name: "Ann").greeting(2), [3, 1, 2].sorted(by: >), [1, 2, 3, 4].filter { $0.isMultiple(of: 2) })
    }
}
