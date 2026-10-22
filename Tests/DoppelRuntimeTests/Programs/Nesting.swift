// Types nested in others: each named with what it's in, so two can share a name.

struct Shop {
    enum Reason: String {
        case damaged, late
    }

    struct Refund {
        let order: Int
        let reason: Reason
        let items: [Item]

        struct Item {
            let name: String
            let reason: Reason
        }

        func describe() -> String {
            "\(order): \(reason.rawValue), \(items.count) items"
        }
    }

    func refund(_ order: Int) -> Refund {
        Refund(order: order, reason: .late, items: [Refund.Item(name: "Tea", reason: Reason.damaged)])
    }
}

struct Warehouse {
    enum Reason {
        case lost
        case broken(count: Int)
    }

    struct Refund {
        let reason: Reason
    }

    func refund() -> Refund {
        Refund(reason: .broken(count: 2))
    }
}

actor Program {
    func run() async {
        let shop = Shop().refund(7)
        print(shop)
        print(shop.describe())
        print([shop.reason])
        print(shop.items)
        let warehouse = Warehouse().refund()
        print(warehouse)
        print([warehouse])
        let reasons: [Warehouse.Reason] = [.lost, warehouse.reason]
        print(reasons)
        let item: Shop.Refund.Item = Shop.Refund.Item(name: "Cup", reason: .late)
        print(item.name, item.reason)
        let maybe: Shop.Reason? = .late
        print(maybe as Any)
    }
}
