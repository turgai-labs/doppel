import Doppel
import DoppelCompilerCheck
import Testing

/// A property's accessors name what they're given as Swift does: a setter's and `willSet`'s new
/// value is `newValue`, `didSet`'s old one is `oldValue`, unless they name it.
@Suite("Accessors are given their values as Swift gives them")
struct AccessorTests {
    @Test(arguments: [
        "private var stored = 0\n    var count: Int {\n        get { stored }\n        set { stored = newValue }\n    }",
        "var count = 0 {\n        willSet { _ = newValue }\n        didSet { _ = oldValue }\n    }",
        "private var stored = 0\n    var count: Int {\n        get { stored }\n        set(given) { stored = given }\n    }",
    ])
    func anAccessorIsGivenItsValue(_ members: String) throws {
        let files = [SwiftCheck.File(name: "Object.swift", code: "actor Counter {\n    \(members)\n}")]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error }
        #expect(swift.isEmpty, "Swift: \(swift)")
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(ours.isEmpty, "\(ours)")
    }
}
