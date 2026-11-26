actor Program {
    func run() {
        let line = "Blur, 13 (Special Edition), Tender,, "
        let parts = line.split(separator: ",")
        print(parts.count, parts.map { String($0) }, parts.map { $0.count })
        print(
            line.split(separator: ",", omittingEmptySubsequences: false).count,
            line.split(separator: ",", maxSplits: 1).count)
        let title: Substring = line.prefix(4)
        print(title, title == "Blur", title.lowercased(), title.hasPrefix("Bl"), "x" + title, title.uppercased())
        var joined = String(title)
        joined += line.dropFirst(6).prefix(2)
        print(joined, [title, line.suffix(7)].joined(separator: "|"))
        print("héllo".utf8.count, Array("hi".utf8), "abc".utf8.reduce(0) { $0 + Int($1) })
        for scalar in "aZ 9".unicodeScalars {
            print(
                scalar, scalar.value, scalar.isASCII, scalar.properties.isAlphabetic, scalar.properties.isUppercase,
                terminator: "; ")
        }
        print()
        if let scalar = Unicode.Scalar(UInt32(0x1F600)) { print(String(scalar), Character(scalar)) }
        let letters: Set<Character> = ["a", "b", "c"]
        var seen = Set<Character>()
        for ch in "banana" { seen.insert(ch) }
        print(
            seen.count, seen.contains("n"), letters.intersection(seen).sorted(), letters.subtracting(seen).sorted(),
            seen.isSubset(of: letters))
        let (inserted, member) = seen.insert("b")
        print(
            inserted, member, seen.remove("z") == nil, seen.union(letters).count, Set("hello").count,
            Array(Set([3, 1, 3])).sorted())
        print(
            letters.filter { $0 != "a" }.sorted(), letters.map { $0.uppercased() }.sorted(),
            Set([1, 2]) == Set([2, 1]))
    }
}
