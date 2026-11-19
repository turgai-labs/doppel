import Doppel
import DoppelCompilerCheck
import Testing

/// A type's static stored property is a constant, as Swift 6 has it: a `static var` is shared
/// mutable state no actor isolates, refused as Swift refuses it.
@Suite("Static stored properties are as Swift 6 allows them")
struct StaticTests {
    @Test(
        arguments: [
            ("static let limit = 16", nil),
            ("private static let names = [\"a\", \"b\"]", nil),
            (
                "static var calls = 0",
                "static property 'calls' is not concurrency-safe because it is nonisolated global shared mutable state"
            ),
            (
                "struct Units {\n        static var scale = 1.8\n    }",
                "static property 'scale' is not concurrency-safe because it is nonisolated global shared mutable state"
            ),
        ] as [(String, String?)])
    func aStaticStoredPropertyIsAConstant(_ member: String, problem: String?) throws {
        let files = [SwiftCheck.File(name: "Object.swift", code: "actor Counter {\n    \(member)\n}")]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error }
            // Without the diagnostic group Swift names: ` [#MutableGlobalVariable]`.
            .map { $0.message.replacing(/\ \[#\w+\]$/, with: "") }
        #expect(swift == (problem.map { [$0] } ?? []), "Swift: \(swift)")
        let ours = SwiftCheck.problems(in: "Object.swift", of: files).map(\.message)
        #expect(ours == swift, "\(ours)")
    }
}
