actor Program {
    func initials(of name: String) -> String {
        var initials = ""
        for word in [name] {
            for ch in word where ch.isUppercase {
                initials.append(ch)
            }
        }
        return initials
    }

    func run() {
        let combined = "Ann Lee" + " 42!"
        var letters = 0
        var digits = 0
        var total = 0
        for ch in combined {
            if ch.isLetter { letters += 1 }
            if let digit = ch.wholeNumberValue {
                digits += 1
                total += digit
            }
        }
        print(letters, digits, total)
        print(initials(of: combined))
        let space: Character = " "
        print(combined.contains(space), combined.contains("!"), combined.first == "A", combined.last ?? "?")
        print(combined.filter { $0 != space }, combined.map { $0.uppercased() }.joined(separator: ""))
        print(String(combined.reversed()), combined.reversed().count)
        var spelled = String(Character("x"))
        spelled.append(Character("y"))
        print(spelled, Character("a") < Character("b"), "\(space)|")
        var result = "a, b, c, "
        result.removeLast()
        let comma = result.removeLast()
        result.removeFirst(3)
        let first = result.removeFirst()
        print(result, comma, first, result.count)
        result.removeAll()
        print(result.isEmpty)
    }
}
