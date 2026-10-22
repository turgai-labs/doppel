import DoppelCompilerCheck
import Testing

/// The compiler's verdict, as the harness reads it.
@Suite("The Swift compiler's verdict")
struct SwiftCompilerTests {
    @Test("an error is read at its file and line")
    func errorsAreRead() throws {
        let diagnostics = try SwiftCompiler().typecheck([
            .init(
                name: "Object.swift",
                code: "actor Counter {\n    var count = 0\n    mutating func add() {\n        count += 1\n    }\n}")
        ])
        #expect(diagnostics.map(\.file) == ["Object.swift"])
        #expect(diagnostics.map(\.line) == [3])
        #expect(diagnostics.first?.message == "'mutating' is not valid on instance methods in classes")
    }

    @Test("code Swift accepts has no errors")
    func acceptedCodeHasNone() throws {
        #expect(
            try SwiftCompiler().typecheck([.init(name: "Object.swift", code: "actor Counter {\n    var count = 0\n}")])
                .isEmpty)
    }
}
