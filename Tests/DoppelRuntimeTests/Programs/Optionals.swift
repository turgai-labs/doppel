// Optional is the standard library's enum: made by its initializer or its cases, matched by them.

struct Parcel {
    var label: String?
}

actor Program {
    func describe(_ value: Int?) -> String {
        switch value {
        case .some(let number) where number > 10: "big \(number)"
        case .some(let number): "small \(number)"
        case .none: "nothing"
        }
    }

    func run() async {
        let made = Optional(3)
        let some = Optional.some("tea")
        let none: Int? = Optional.none
        let specialized = Optional<String>("cup")
        print(made as Any, some as Any, none as Any, specialized as Any)
        print(describe(made), describe(Optional(12)), describe(.none))
        let doubled = made.map { $0 * 2 }
        print(doubled as Any, made.flatMap { $0 > 5 ? $0 : nil } as Any)
        let values: [Int?] = [Optional(1), nil, .some(3)]
        print(values)
        if case .some(let number) = made {
            print("has", number)
        }
        let parcel = Parcel(label: Optional("fragile"))
        print(parcel.label ?? "none", parcel)
        print(made == 3, none == nil, Optional(3) == made)
    }
}
