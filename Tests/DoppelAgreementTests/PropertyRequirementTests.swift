import Doppel
import DoppelCompilerCheck
import Testing

/// A protocol's property is met as Swift meets it: by one of its name and type, settable when it
/// must be set, and, on an actor, only for a protocol of actors or an `async` getter.
@Suite("A protocol's properties are met as Swift meets them")
struct PropertyRequirementTests {
    @Test(
        arguments: [
            // Met, by an actor, for a protocol of actors: computed, stored, constant.
            (
                "protocol Shown: Actor {\n    var layout: Int { get }\n}",
                "actor Page: Shown {\n    var layout: Int { 1 }\n}"
            ),
            ("protocol Shown: Actor {\n    var layout: Int { get }\n}", "actor Page: Shown {\n    var layout = 1\n}"),
            ("protocol Shown: Actor {\n    var layout: Int { get }\n}", "actor Page: Shown {\n    let layout = 1\n}"),
            // Missing, or of another type.
            ("protocol Shown: Actor {\n    var layout: Int { get }\n}", "actor Page: Shown {\n    var count = 0\n}"),
            (
                "protocol Shown: Actor {\n    var layout: Int { get }\n}",
                "actor Page: Shown {\n    var layout: String { \"\" }\n}"
            ),
            // Set too: a getter alone doesn't meet it.
            (
                "protocol Shown: Actor {\n    var layout: Int { get set }\n}",
                "actor Page: Shown {\n    var layout: Int { 1 }\n}"
            ),
            (
                "protocol Shown: Actor {\n    var layout: Int { get set }\n}",
                "actor Page: Shown {\n    var layout = 1\n}"
            ),
            // An actor's own state, for a protocol that isn't of actors: only an `async` getter.
            ("protocol Shown {\n    var layout: Int { get }\n}", "actor Page: Shown {\n    var layout: Int { 1 }\n}"),
            (
                "protocol Shown {\n    var layout: Int { get async }\n}",
                "actor Page: Shown {\n    var layout: Int { 1 }\n}"
            ),
            // A struct meets it with what it holds.
            ("protocol Shown {\n    var layout: Int { get }\n}", "struct Page: Shown {\n    let layout = 1\n}"),
        ] as [(String, String)])
    func aPropertyIsMetAsSwiftMeetsIt(_ declared: String, _ code: String) throws {
        let files = [
            SwiftCheck.File(name: "Object.swift", code: code), SwiftCheck.File(name: "Objects.swift", code: declared),
        ]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error && $0.file == "Object.swift" }
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(
            ours.map(\.line) == swift.map(\.line),
            "Swift: \(swift.map { "\($0.line): \($0.message)" }), Doppel: \(ours.map { "\($0.line): \($0.message)" })")
    }
}
