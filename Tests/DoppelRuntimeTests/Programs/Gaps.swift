import Foundation

actor Program {
    /// A value read like JSON: a subscript of its own, by key and by position.
    struct Node {
        var fields: [String: Int]
        var items: [Int]

        subscript(key: String) -> Int? { fields[key] }
        subscript(index: Int) -> Int { items[index] }
    }

    func run() {
        // Numbers formatted as text.
        print(String(format: "%.4f", 52.520008), String(format: "%.1f °C", 8.94), String(format: "%d%%", 87))
        print(String(format: "%02d:%02d", 7, 5))

        // One-sided ranges.
        let timestamp = "2026-11-19T12:30"
        if let separator = timestamp.firstIndex(of: "T") {
            print(String(timestamp[timestamp.index(after: separator)...]), String(timestamp[..<separator]))
        }
        let numbers = [1, 2, 3, 4, 5]
        print(Array(numbers[2...]), Array(numbers[..<2]), Array(numbers[...1]))

        // Unicode.Scalar by its other name.
        if let scalar = UnicodeScalar(233) { print(Character(scalar), scalar.value) }

        // An own type's subscripts.
        let node = Node(fields: ["is_day": 1], items: [10, 20])
        print(node["is_day"] ?? -1, node["missing"] ?? -1, node[1])
    }
}
