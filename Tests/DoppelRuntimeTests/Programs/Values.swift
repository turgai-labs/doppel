struct Point: Equatable {
    var x: Double
    var y: Double = 0
    let name: String

    mutating func move(by dx: Double) {
        x += dx
    }

    var length: Double { x * x + y * y }
}

enum Status: String {
    case placed
    case refunded = "back"
    case denied
}

enum Item {
    case text(words: String)
    case button(label: String)
    case pair(Int, Int)
}

actor Program {
    var points: [Point] = []
    var count = 0

    func run() async {
        var unset: Int?
        print(unset == nil)
        unset = 1
        var a = Point(x: 1, name: "a")
        let b = a
        a.move(by: 2)
        print(a.x, b.x, a == b, a.length)
        print(a)
        points.append(a)
        points[0].x = 10
        print(points[0].x, a.x)

        print(Status.refunded.rawValue, Status(rawValue: "denied") == .denied, Status(rawValue: "nope") == nil)
        let items: [Item] = [.text(words: "hi"), .button(label: "Go"), .pair(1, 2)]
        for item in items {
            switch item {
            case .text(let words): print("text", words)
            case .button(let label): print("button", label)
            case .pair(let x, let y) where x < y: print("pair", x + y)
            case .pair: print("other pair")
            }
        }
        print(items[0])
        // An implicit member takes its type from what the closure is expected to return.
        let names = ["a", "", "c"]
        let texts: [Item] = names.map { name in
            let upper = name.uppercased()
            return .text(words: upper)
        }
        let short: [Item] = names.map { .text(words: $0) }
        let some: [Item] = names.compactMap { $0.isEmpty ? nil : .button(label: $0) }
        print(texts.count, short.count, some.count, some)

        let maybe: Int? = 3
        let none: Int? = nil
        print(maybe ?? 0, none ?? 7, maybe.map { $0 * 2 } ?? 0, "\(maybe as Any)")
        if let maybe, maybe > 2 { print("bound", maybe) }
        guard let value = maybe else { return }
        print("guarded \(value)")
        let named: Point? = Point(x: 3, y: 4, name: "c")
        print(named?.length ?? -1, named?.name.uppercased() ?? "")
    }
}
