struct Percent {
    let value: Int

    init?(_ value: Int) {
        guard (0...100).contains(value) else {
            return nil
        }
        self.value = value
    }

    init?(text: String) {
        if text.isEmpty { return nil }
        guard let number = Int(text), (0...100).contains(number) else { return nil }
        value = number
    }
}

enum Size {
    case small, large

    init?(code: String) {
        switch code {
        case "S": self = .small
        case "L": self = .large
        default: return nil
        }
    }
}

actor Program {
    func run() {
        print(Percent(42)?.value ?? -1, Percent(142) == nil, Percent(-1)?.value ?? -1)
        if let half = Percent(50) {
            print(half.value)
        }
        print(Percent(text: "7")?.value ?? -1, Percent(text: "") == nil, Percent(text: "x") == nil, Percent(text: "700") == nil)
        print(Size(code: "S") == .small, Size(code: "M") == nil)
        let sizes = ["S", "M", "L"].compactMap { Size(code: $0) }
        print(sizes.count)
    }
}
