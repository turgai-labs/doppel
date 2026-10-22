// `nil` is a literal any type can take, by conforming to `ExpressibleByNilLiteral`: an optional's
// is its `.none`, another type's is what its `init(nilLiteral:)` makes.

struct Note: ExpressibleByNilLiteral, Equatable {
    var text: String

    init(text: String) {
        self.text = text
    }

    init(nilLiteral: ()) {
        text = "(blank)"
    }
}

enum Mark: ExpressibleByNilLiteral, Equatable {
    case none
    case tick

    init(nilLiteral: ()) {
        self = .none
    }
}

actor Program {
    func label(_ note: Note) -> String {
        note.text
    }

    func run() async {
        let blank: Note = nil
        print(blank.text, label(nil), label(Note(text: "milk")))
        var mark: Mark = .tick
        print(mark, mark == nil)
        mark = nil
        print(mark, mark == nil, nil == mark)
        let notes: [Note] = [nil, Note(text: "eggs")]
        print(notes.map(\.text))
        let maybe: Note? = nil
        print(maybe as Any)
    }
}
