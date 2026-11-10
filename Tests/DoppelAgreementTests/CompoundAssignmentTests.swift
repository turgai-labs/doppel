import Doppel
import DoppelCompilerCheck
import Testing

/// Compound assignments, as Swift checks them. Each refusal is the Swift compiler's own, at its
/// line.
@Suite("Compound assignments are checked as Swift checks them")
struct CompoundAssignmentTests {
    /// A shift's amount is an integer, whichever way it shifts.
    @Test(arguments: ["<<=", ">>="])
    func aShiftByANonIntegerIsRefused(_ shift: String) throws {
        let files = [
            SwiftCheck.File(
                name: "Object.swift",
                code:
                    "actor Counter {\n    var count = 1\n    func shift(by amount: Double) {\n        count \(shift) amount\n    }\n}"
            )
        ]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error }
        #expect(swift.map(\.line) == [4], "Swift: \(swift)")
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(ours.map(\.message) == swift.map(\.message))
        #expect(ours.map(\.line) == swift.map(\.line))
    }
}
