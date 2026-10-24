struct Pair<First, Second> {
    let first: First
    let second: Second
}

actor Program {
    func named<T>(_ type: T.Type) -> String {
        "\(type)"
    }

    func values<T>(of type: T.Type, from given: [T]) -> [T] {
        given
    }

    func run() async {
        print(Int.self, [Int].self, String?.self, [String: Int].self)
        print(named(Double.self), named(Pair<Int, String>.self))
        let numbers = values(of: Int.self, from: [3, 4])
        print(numbers.count, numbers.reduce(0, +))
        let type: Int.Type = Int.self
        print(type, "\(Bool.self) and \(Character.self)")
    }
}
