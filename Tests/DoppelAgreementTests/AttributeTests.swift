import Doppel
import DoppelCompilerCheck
import Testing

/// Attributes, as Swift checks them: one that isn't declared is refused, a declaration modifier
/// written as one is said to be one, and a macro takes the arguments it's declared with and
/// attaches where its roles let it. Each refusal is the Swift compiler's own, at its line.
@Suite("Attributes are checked as Swift checks them")
struct AttributeTests {
    static let runtime = """
        @attached(accessor) macro Subscribed() = #externalMacro(module: "Objects", type: "SubscribedMacro")
        @attached(extension, conformances: Codable) macro Event() = #externalMacro(module: "Objects", type: "EventMacro")
        """

    static func module(_ members: String) -> [SwiftCheck.File] {
        [
            SwiftCheck.File(name: "Runtime.swift", code: runtime),
            SwiftCheck.File(name: "Object.swift", code: "actor Counter {\n    \(members)\n}"),
        ]
    }

    @Test(arguments: [
        ("@Stored var count = 0", "unknown attribute 'Stored'"),
        ("@Subscribed(to: \"shop\") var count = 0", "argument passed to macro expansion that takes no arguments"),
        ("@Subscribed func add() {}", "'accessor' macro cannot be attached to instance method ('add')"),
        ("@Event var count = 0", "'extension' macro cannot be attached to property ('count')"),
    ])
    func aMisusedAttributeIsRefusedAsSwiftRefusesIt(_ members: String, _ refusal: String) throws {
        let files = Self.module(members)
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error && $0.file == "Object.swift" }
        #expect(swift.map(\.message) == [refusal], "Swift: \(swift)")
        #expect(swift.map(\.line) == [2])
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(ours.map(\.message) == [refusal])
        #expect(ours.map(\.line) == [2])
    }

    /// A declaration modifier written as an attribute is one: `@actor` is `actor`.
    @Test func aModifierWrittenAsAnAttributeIsSaidToBeOne() throws {
        let files = [SwiftCheck.File(name: "Object.swift", code: "@actor Counter {\n    var count = 0\n}")]
        let swift = try SwiftCompiler().typecheck(files.map { .init(name: $0.name, code: $0.code) })
            .filter { $0.severity == .error }
        #expect(swift.map(\.message).contains("'actor' is a declaration modifier, not an attribute"), "Swift: \(swift)")
        let ours = SwiftCheck.problems(in: "Object.swift", of: files)
        #expect(
            ours.contains { $0.message == "'actor' is a declaration modifier, not an attribute" && $0.line == 1 },
            "\(ours)")
    }

    /// A macro used as it's declared, and the attributes Swift has, are taken. Swift can't expand
    /// a macro without its implementation, which the runtime has, so only Doppel is asked.
    @Test func attributesUsedAsDeclaredAreTaken() {
        let ours = SwiftCheck.problems(
            in: "Object.swift",
            of: Self.module(
                "@Subscribed var count = 0\n    @Event struct Added { var count: Int }\n    @discardableResult func add() -> Int { 1 }"
            ))
        #expect(ours.isEmpty, "\(ours)")
    }
}
