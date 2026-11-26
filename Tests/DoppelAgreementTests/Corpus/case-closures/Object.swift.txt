enum Inner {
    case text(words: String)
}

actor Page {
    var names: [String] = ["a", "b"]
    var separator = "—"

    func items() -> [Inner] {
        let mapped: [Inner] = names.map { name in
            let upper = name.uppercased()
            return .text(words: "\(upper) \(separator)")
        }
        let short: [Inner] = names.map { .text(words: $0) }
        let some: [Inner] = names.compactMap { $0.isEmpty ? nil : .text(words: $0) }
        return mapped + short + some
    }

    func biggest(_ amounts: [Double]) -> Double {
        amounts.reduce(0) { max($0, $1) }
    }

    func later() {
        Task {
            try await Task.sleep(for: .seconds(1))
            names.append("c")
        }
    }

    func wrongType() -> [Inner] {
        names.map { .button(label: $0) }
    }
}
