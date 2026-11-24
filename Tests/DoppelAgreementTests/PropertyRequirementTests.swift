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

    /// A property in a type has its accessors' bodies: one written as a protocol requires it,
    /// `{ get }`, is refused as Swift refuses it.
    @Test(
        arguments: [
            "actor Page {\n    var layout: Int { get }\n}",
            "struct Page {\n    var layout: Int { get set }\n}",
            "actor Page {\n    var layout: Int { 1 }\n}",
            "actor Page {\n    var layout: Int { get { 1 } }\n}",
        ])
    func accessorsHaveBodies(_ code: String) throws {
        let files = [SwiftCheck.File(name: "Object.swift", code: code)]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error && $0.file == "Object.swift" }
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(
            ours.map(\.line) == swift.map(\.line),
            "Swift: \(swift.map { "\($0.line): \($0.message)" }), Doppel: \(ours.map { "\($0.line): \($0.message)" })")
    }

    /// A type that doesn't conform is told what's missing as Swift's notes say it: each requirement
    /// it doesn't meet, with its type.
    @Test(
        arguments: [
            (
                "protocol Shown: Actor {\n    var layout: Int { get }\n}",
                "actor Page: Shown {\n    var body: Int { 1 }\n}"
            ),
            (
                "protocol Asks: Actor {\n    func ask(_ question: String) async -> String\n}",
                "actor Desk: Asks {\n    func ask(_ question: Int) -> String { \"\" }\n}"
            ),
            (
                "protocol Both: Actor {\n    var layout: Int { get }\n    func pressed(_ label: String)\n}",
                "actor Page: Both {\n    var count = 0\n}"
            ),
        ] as [(String, String)])
    func whatsMissingIsSaid(_ declared: String, _ code: String) throws {
        let files = [
            SwiftCheck.File(name: "Object.swift", code: code), SwiftCheck.File(name: "Objects.swift", code: declared),
        ]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .note && $0.message.hasPrefix("protocol requires") }.map(\.message)
        let ours = SwiftCheck.problems(in: "Object.swift", of: files).flatMap(\.notes)
        #expect(Set(ours) == Set(swift), "Swift: \(swift), Doppel: \(ours)")
        #expect(!ours.isEmpty)
    }
}
