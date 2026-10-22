enum Status: String {
    case placed, refunded, denied
}

enum Item {
    case text(words: String)
    case button(label: String)
}

actor Orders {
    var status: Status = .placed
    var items: [Item] = []

    func describe() -> String {
        switch status {
        case .placed: return "placed"
        case .refunded, .denied: return status.rawValue
        }
    }

    func labels() -> [String] {
        var labels: [String] = []
        for item in items {
            if case .button(let label) = item {
                labels.append(label)
            }
        }
        return labels
    }

    func words(of item: Item) -> String {
        switch item {
        case .text(let words): words
        case let .button(label): label
        }
    }

    func incomplete(of item: Item) -> String {
        switch item {
        case .text(let words): return words
        }
    }

    func parse(_ raw: String) -> Status? {
        Status(rawValue: raw)
    }
}
