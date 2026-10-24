/// A box of a value, with a label of the same value: a type nested in a generic type.
struct Box<Value> {
    struct Label {
        let value: Value
        let note: String

        func shown() -> String { "\(note): \(value)" }
    }

    let label: Label

    init(_ value: Value, note: String) {
        label = Label(value: value, note: note)
    }

    func relabeled(_ note: String) -> Label {
        Label(value: label.value, note: note)
    }
}

actor Program {
    var kept: Box<Int>.Label?

    func run() async {
        let box = Box(3, note: "three")
        print(box.label.shown())
        let named: Box<String>.Label = Box("tea", note: "drink").relabeled("hot drink")
        print(named.shown(), named.value.count)
        kept = box.relabeled("kept")
        print(kept?.shown() ?? "none", (kept?.value ?? 0) + 1)
    }
}
