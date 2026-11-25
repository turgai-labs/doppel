import Doppel
import DoppelCompilerCheck
import Testing

/// What an initializer may return, as Swift has it: a failable one `nil`, and no initializer
/// anything else.
@Suite("Initializers return as Swift allows them")
struct FailableInitializerTests {
    @Test(
        arguments: [
            (
                "init?(value: Int) {\n        guard value > 0 else { return nil }\n        self.value = value\n    }",
                nil
            ),
            (
                "init(value: Int) {\n        return nil\n    }",
                "only a failable initializer can return 'nil'"
            ),
            (
                "init?(value: Int) {\n        return 5\n    }",
                "'nil' is the only return value permitted in an initializer"
            ),
        ] as [(String, String?)])
    func anInitializerReturnsAsSwiftAllows(_ initializer: String, problem: String?) throws {
        let files = [
            SwiftCheck.File(name: "Object.swift", code: "struct Positive {\n    let value: Int\n    \(initializer)\n}")
        ]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error }
        #expect(swift.map(\.message) == (problem.map { [$0] } ?? []), "Swift: \(swift.map(\.message))")
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(ours.map(\.message) == swift.map(\.message), "\(ours.map(\.message))")
        #expect(ours.map(\.line) == swift.map(\.line))
    }
}
