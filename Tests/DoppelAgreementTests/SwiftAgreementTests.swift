import Doppel
import DoppelCompilerCheck
import Foundation
import Testing

/// Every module in the corpus, checked by the Swift compiler and by Doppel: each must say the
/// same of its object's file, that it's right or at which lines it's wrong.
///
/// A corpus module is plain Swift: the module the code imports (`Objects.swift`), its runtime
/// (`Runtime.swift`), and the code (`Object.swift`). Doppel goes beyond Swift in one way: a
/// method called on an `Object`, which is `any Actor`, is a message, which Swift can't type, so
/// Swift's refusals of those calls aren't counted.
@Suite("Doppel checks code as Swift does")
struct DoppelAgreementTests {
    /// How many of the corpus's modules Doppel's resolver has come to agree with Swift on: it
    /// never agrees on fewer. Raise it as checking comes closer to Swift's, until it's all of them.
    static let agreedOnAtLeast = 72

    @Test func everyCorpusModuleIsCheckedAsSwiftChecksIt() async throws {
        let compiler = try SwiftCompiler()
        var verdicts: [Verdict: [String]] = [:]
        for module in try Module.corpus() {
            let said = try compiler.typecheck(module.files).filter { $0.severity == .error }
            let swift = said.filter { !Module.isMessageToObject($0) }
            // A line with a message to an `Object` Swift can't type, so it says nothing else of it:
            // what Doppel says of it isn't compared either.
            let untyped = Set(said.filter { Module.isMessageToObject($0) && $0.file == Module.objectFile }.map(\.line))
            let ours = module.resolved().filter { !untyped.contains($0.0) }
            let verdict = Verdict(swift: swift, ours: ours)
            guard verdict != .agree else {
                verdicts[verdict, default: []].append(module.name)
                continue
            }
            verdicts[verdict, default: []].append(
                """
                \(module.name):
                  Swift:       \(swift.isEmpty ? "accepts" : swift.map { "\($0.file == Module.objectFile ? "\($0.line)" : "(\($0.file))"): \($0.message)" }.joined(separator: "\n               "))
                  Doppel: \(ours.isEmpty ? "accepts" : ours.map { "\($0.0): \($0.1)" }.joined(separator: "\n               "))
                """)
        }
        let total = verdicts.values.map(\.count).reduce(0, +)
        var report = Verdict.allCases.map { "\($0.rawValue): \(verdicts[$0]?.count ?? 0) of \(total)" }.joined(
            separator: "\n")
        for verdict in Verdict.allCases where verdict != .agree {
            report += "\n\n## \(verdict.rawValue)\n\n" + (verdicts[verdict] ?? []).joined(separator: "\n\n")
        }
        if let path = ProcessInfo.processInfo.environment["SWIFT_AGREEMENT_REPORT"] {
            try report.write(toFile: path, atomically: true, encoding: .utf8)
        }
        let agreed = verdicts[.agree]?.count ?? 0
        #expect(agreed >= Self.agreedOnAtLeast, "Agrees with Swift on fewer than before:\n\(report)")
    }

    /// How Doppel's verdict on code compares with Swift's.
    enum Verdict: String, CaseIterable, Hashable {
        /// Both accept it, or both refuse it at the same lines.
        case agree = "Agree"
        /// Swift accepts it; Doppel refuses it.
        case wronglyRefused = "Swift accepts, Doppel refuses"
        /// Swift refuses it; Doppel accepts it.
        case missed = "Swift refuses, Doppel accepts"
        /// Both refuse it, at different lines.
        case otherLines = "Both refuse, at different lines"

        init(swift: [SwiftCompiler.Diagnostic], ours: [(Int, String)]) {
            switch (swift.isEmpty, ours.isEmpty) {
            case (true, true): self = .agree
            case (true, false): self = .wronglyRefused
            case (false, true): self = .missed
            case (false, false):
                let swiftLines = Set(swift.filter { $0.file == Module.objectFile }.map(\.line))
                self = swiftLines == Set(ours.map(\.0)) ? .agree : .otherLines
            }
        }
    }
}

/// A corpus module: plain Swift files, one of them the object's code.
struct Module {
    static let objectFile = "Object.swift"

    let name: String
    let files: [SwiftCompiler.File]

    var code: String { files.first { $0.name == Self.objectFile }?.code ?? "" }
    var given: [SwiftCompiler.File] { files.filter { $0.name != Self.objectFile } }

    static func corpus() throws -> [Module] {
        let directory = try #require(Bundle.module.url(forResource: "Corpus", withExtension: nil))
        let manager = FileManager.default
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { folder in
                let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    .filter { $0.pathExtension == "swift" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    .map {
                        SwiftCompiler.File(
                            name: $0.lastPathComponent, code: try String(contentsOf: $0, encoding: .utf8))
                    }
                return Module(name: folder.lastPathComponent, files: files)
            }
    }

    /// Swift's refusal of a method called on an `Object`, which Doppel sends as a message.
    static func isMessageToObject(_ diagnostic: SwiftCompiler.Diagnostic) -> Bool {
        diagnostic.message.contains("value of type 'any Actor' has no member")
            || diagnostic.message.contains("value of type 'Object' (aka 'any Actor') has no member")
    }

    /// What Doppel's resolver says of the object's file, given the rest of the module.
    func resolved() -> [(Int, String)] {
        SwiftCheck.problems(in: Self.objectFile, of: files.map { SwiftCheck.File(name: $0.name, code: $0.code) }).map {
            ($0.line, $0.message)
        }
    }

}
