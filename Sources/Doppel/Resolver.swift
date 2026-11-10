import SwiftDiagnostics
import SwiftOperators
import SwiftParser
import SwiftParserDiagnostics
package import SwiftSyntax

/// What Swift says of a file of a module, decided as Swift decides it: its syntax, then every name
/// and type in it, resolved. Only the file is checked; the module's other files are what it's
/// given, and are known to compile.
public enum SwiftCheck {
    /// A file of the module: its name, and its code.
    public struct File: Sendable {
        public let name: String
        public let code: String

        public init(name: String, code: String) {
            self.name = name
            self.code = code
        }
    }

    /// What's wrong at a line of the file, in Swift's words.
    public struct Diagnostic: Sendable, Equatable, CustomStringConvertible {
        public let line: Int
        public let column: Int
        public let message: String
        /// The code it's about, as written, on one line, when it's known.
        public let code: String?

        public var description: String { "\(line):\(column): \(message)" }

        public init(line: Int, column: Int, message: String, code: String? = nil) {
            self.line = line
            self.column = column
            self.message = message
            self.code = code
        }
    }

    /// What Swift would refuse in the file named `file`, given the rest of `files`, at the lines
    /// it's at, in order.
    public static func problems(in file: String, of files: [File]) -> [Diagnostic] {
        resolve(file, of: files).problems
    }

    /// The problems in the standard library's own Swift as `file` uses it: none, when Doppel
    /// is right.
    package static func libraryProblems(in file: String, of files: [File]) -> [String] {
        let parsed = files.map { ($0.name, Self.folded(Parser.parse(source: $0.code))) }
        guard let checked = parsed.first(where: { $0.0 == file })?.1 else { return [] }
        let resolver = Resolver(
            module: Module(files: parsed), checked: checked, named: file,
            lines: SourceLocationConverter(fileName: file, tree: checked))
        resolver.resolveFile()
        return resolver.libraryProblems
    }

    /// Where Swift says a syntax problem is: at its node, or for a token that's missing, where
    /// the next token there is starts, or the file ends.
    static func position(of node: Syntax, in file: SourceFileSyntax) -> AbsolutePosition {
        guard let token = node.as(TokenSyntax.self) ?? node.firstToken(viewMode: .all), token.presence == .missing
        else {
            return node.positionAfterSkippingLeadingTrivia
        }
        var next = token.nextToken(viewMode: .sourceAccurate)
        while let candidate = next, candidate.presence == .missing {
            next = candidate.nextToken(viewMode: .sourceAccurate)
        }
        return next?.positionAfterSkippingLeadingTrivia ?? file.endPosition
    }

    /// The file resolved against the rest, ready to run when nothing's wrong with it: its problems,
    /// and when there are none, the program.
    package static func resolve(_ file: String, of files: [File]) -> (problems: [Diagnostic], program: ResolvedProgram?)
    {
        let parsed = files.map { ($0.name, Self.folded(Parser.parse(source: $0.code))) }
        guard let checked = parsed.first(where: { $0.0 == file })?.1 else { return ([], nil) }
        let lines = SourceLocationConverter(fileName: file, tree: checked)
        var problems = ParseDiagnosticsGenerator.diagnostics(for: checked).map { diagnostic in
            let location = lines.location(for: Self.position(of: diagnostic.node, in: checked))
            return Diagnostic(line: location.line, column: location.column, message: diagnostic.message)
        }
        let resolver = Resolver(module: Module(files: parsed), checked: checked, named: file, lines: lines)
        resolver.resolveFile()
        problems += resolver.diagnostics
        problems.sort { ($0.line, $0.column) < ($1.line, $1.column) }
        return (problems, problems.isEmpty ? ResolvedProgram(resolver: resolver) : nil)
    }

    /// Operators folded by their precedence, as the compiler reads `a + b * c`.
    static func folded(_ file: SourceFileSyntax) -> SourceFileSyntax {
        OperatorTable.standardOperators.foldAll(file) { _ in }.as(SourceFileSyntax.self) ?? file
    }
}

/// Resolves a file's code against its module: every name to what it is, every expression to its
/// type, as Swift's type checker does for the subset objects are written in. What it can't resolve
/// it says, in Swift's words, where Swift would.
final class Resolver {
    let module: Module
    let checked: SourceFileSyntax
    /// The name of the file it checks.
    let checkedName: String
    let lines: SourceLocationConverter
    private(set) var diagnostics: [SwiftCheck.Diagnostic] = []
    /// Problems in the standard library's own Swift, as it's resolved for a type it's used on.
    private(set) var libraryProblems: [String] = []
    var resolved = ResolvedModule()

    /// The function being resolved, and the scopes of names within it.
    var context: FunctionContext!
    /// Whether the expression being resolved is marked `try`, and how, and `await`.
    var marks = Marks()
    /// The call or property access being resolved: where its effects are said to need `try` or
    /// `await`.
    var effectSite: Syntax?
    /// Values each optional chain's rest reads its base's value as.
    var chains: [SyntaxIdentifier: Typed] = [:]
    /// Each function's resolved body, made once.
    var bodies: [ObjectIdentifier: ResolvedFunction] = [:]
    /// The standard library's functions written in Swift, each resolved once for each type it's
    /// used on.
    var specialized: [String: ResolvedFunction] = [:]
    /// Each call's generic parameters, as the call that's made binds them, by where it's written.
    var callBindings: [SyntaxIdentifier: [String: SwiftType]] = [:]
    /// Each property's inferred type, once it's resolved.
    var inferred: [String: SwiftType] = [:]
    /// Each stored property's starting value, by `Type.name`.
    var startingValues: [String: StartingValue] = [:]

    init(module: Module, checked: SourceFileSyntax, named name: String, lines: SourceLocationConverter) {
        self.module = module
        self.checked = checked
        self.checkedName = name
        self.lines = lines
    }

    struct Marks {
        enum Try { case plain, optional, forced }
        var tried: Try?
        var awaited = false
    }

    // MARK: Diagnostics

    private var speculating = 0
    private var failedSpeculatively = false

    func report(_ message: String, at node: some SyntaxProtocol) {
        if speculating > 0 {
            failedSpeculatively = true
            return
        }
        // A problem in the standard library's Swift is Doppel's, not the code's: it's kept
        // apart, for Doppel's tests to see.
        if node.root.id == StandardLibrary.syntax.root.id {
            libraryProblems.append("\(message): `\(node.trimmedDescription.prefix(120))`")
            return
        }
        guard node.root.id == checked.root.id else { return }
        let location = lines.location(for: node.positionAfterSkippingLeadingTrivia)
        let written = node.trimmedDescription
        let diagnostic = SwiftCheck.Diagnostic(
            line: location.line, column: location.column, message: message,
            code: written.contains("\n") || written.isEmpty ? nil : written)
        if !diagnostics.contains(diagnostic) { diagnostics.append(diagnostic) }
    }

    /// `body`'s result, and whether it resolved without a problem, without saying any it had: for
    /// trying one overload of several.
    func speculate<T>(_ body: () -> T?) -> T? {
        let (failedBefore, marksBefore, chainsBefore) = (failedSpeculatively, marks, chains)
        let unassignedBefore = context?.unassigned
        speculating += 1
        failedSpeculatively = false
        let result = body()
        let failed = failedSpeculatively
        speculating -= 1
        failedSpeculatively = failedBefore
        marks = marksBefore
        chains = chainsBefore
        if let unassignedBefore { context.unassigned = unassignedBefore }
        return failed ? nil : result
    }

    // MARK: Conversions

    /// `value` as `target`, as Swift converts it implicitly: wrapped into an optional, erased to
    /// an existential, or as it is. `nil`, having said why, when it isn't one.
    func convert(_ value: Typed, to target: SwiftType, at node: some SyntaxProtocol, as role: ConversionRole) -> Typed?
    {
        if let converted = converted(value, to: target) { return converted }
        report(role.message(value.type, target), at: node)
        return nil
    }

    func converted(_ value: Typed, to target: SwiftType) -> Typed? {
        let source = value.type
        if source == target { return value }
        switch (source, target) {
        case (.never, _), (.unresolved, _), (_, .unresolved): return Typed(value.expression, target)
        case (.dynamic, _): return Typed(.cast(value, target, .forced), target)
        case (_, .dynamic): return value
        case (_, .existential(let protocols)):
            guard protocols.allSatisfy({ conforms(source, to: $0) }) else { return nil }
            if case .existential(let held) = source, Set(protocols).isSubset(of: held) {
                return Typed(value.expression, target)
            }
            return Typed(.erase(value), target)
        case (.optional(let sourceWrapped), .optional(let targetWrapped)):
            if case .nil = value.expression { return Typed(.nil, target) }
            // An optional's value, converted when it has one: `Int?` as `Any?`.
            guard let inner = converted(Typed(.chained, sourceWrapped), to: targetWrapped) else { return nil }
            if case .chained = inner.expression { return Typed(value.expression, target) }
            return Typed(.chain(value, inner), target)
        case (_, .optional(let wrapped)):
            return converted(value, toWrapped: wrapped, target)
        case (.tuple(let elements, _), .tuple(let targets, _)) where elements == targets:
            return Typed(value.expression, target)
        case (.array(let element), .array(let targetElement)):
            // An array is as its elements convert: `[Int]` as `[Int?]` or `[Any]`.
            guard converted(Typed(.chained, element), to: targetElement) != nil else { return nil }
            return Typed(.cast(value, target, .forced), target)
        case (
            .function(let parameters, let result, let effects),
            .function(let targetParameters, let targetResult, let targetEffects)
        ):
            guard parameters == targetParameters, result == targetResult || targetResult == .void,
                !effects.async || targetEffects.async, !effects.throwing || targetEffects.throwing
            else { return nil }
            // A function is the same function as a wider type: what it does is still its own.
            return value
        default:
            return nil
        }
    }

    private func converted(_ value: Typed, toWrapped wrapped: SwiftType, _ target: SwiftType) -> Typed? {
        guard let inner = converted(value, to: wrapped) else { return nil }
        return Typed(.wrap(inner), target)
    }

    enum ConversionRole {
        case argument, binding, returned, assigned, element, condition

        func message(_ source: SwiftType, _ target: SwiftType) -> String {
            switch self {
            case .argument: "cannot convert value of type '\(source)' to expected argument type '\(target)'"
            case .binding: "cannot convert value of type '\(source)' to specified type '\(target)'"
            case .returned: "cannot convert return expression of type '\(source)' to return type '\(target)'"
            case .assigned: "cannot assign value of type '\(source)' to type '\(target)'"
            case .element: "cannot convert value of type '\(source)' to expected element type '\(target)'"
            case .condition: "cannot convert value of type '\(source)' to expected condition type 'Bool'"
            }
        }
    }

    /// Whether a value of `type` conforms to `protocolName`, as declared or as Swift gives it.
    func conforms(_ type: SwiftType, to protocolName: String) -> Bool {
        switch protocolName {
        case "Sendable", "Any": return true
        case "BinaryInteger", "FixedWidthInteger": return type.isInteger
        case "Equatable", "Hashable":
            switch type {
            case .int, .double, .bool, .string, .character, .fixedInteger, .never: return true
            case .optional(let wrapped), .array(let wrapped): return conforms(wrapped, to: protocolName)
            case .dictionary(let key, let value):
                return conforms(key, to: "Hashable") && conforms(value, to: protocolName)
            case .tuple(let elements, _):
                return protocolName == "Equatable" && elements.count <= 6
                    && elements.allSatisfy { conforms($0, to: "Equatable") }
            default: break
            }
        case "Comparable":
            switch type {
            case .int, .double, .string, .character, .fixedInteger: return true
            default: break
            }
        default: break
        }
        switch type {
        case .named(let name, _):
            guard let declaration = module.type(named: name) else { return false }
            return module.protocols(of: declaration).contains(protocolName)
        case .existential(let protocols):
            return protocols.contains(protocolName)
                || protocols.contains { module.type(named: $0)?.refines.contains(protocolName) == true }
        case .dynamic, .unresolved:
            return true
        default:
            // A standard type, as its declaration and extensions conform it: `String` to `Collection`.
            guard let name = type.declarationName, let declaration = module.type(named: name) else { return false }
            return module.protocols(of: declaration).contains(protocolName)
        }
    }
}

/// A stored property's starting value, with how many locals its closures need.
package struct StartingValue {
    package let value: Typed
    package let slots: Int
}

/// A file resolved against its module, with nothing wrong: its types, its functions' bodies and
/// its starting values, as the evaluator runs them.
package struct ResolvedProgram {
    let resolver: Resolver

    /// The file it runs: what's declared elsewhere is the host's.
    package var file: SourceFileSyntax { resolver.checked }

    package func type(named name: String) -> TypeDeclaration? { resolver.module.type(named: name) }

    package func body(of function: Function) -> ResolvedFunction { resolver.resolvedBody(of: function) }

    package func startingValue(of property: Property, in type: TypeDeclaration) -> StartingValue? {
        resolver.startingValue(of: property, in: type)
    }

    /// Whether a declaration is the file's own, which runs here, rather than the host's.
    package func isOwn(_ syntax: Syntax?) -> Bool { syntax?.root.id == resolver.checked.root.id }

    /// Whether a function's body runs here: the file's own, or the standard library's written in
    /// Swift, rather than the host's.
    package func runsHere(_ syntax: Syntax?) -> Bool {
        isOwn(syntax) || syntax?.root.id == StandardLibrary.syntax.root.id
    }

    /// A global's value, in whichever file declares it: what its initializer runs.
    package func global(_ name: String) -> Typed? {
        guard resolver.module.globals[name] != nil else { return nil }
        _ = resolver.globalType(name)
        return resolver.resolved.globals.first { $0.name == name }?.value
    }

    package func isStandard(_ function: Function) -> Bool { resolver.isStandard(function) }
}

/// A function or closure being resolved: what `self` is in it, what it may do, and what it
/// returns; its frame of locals, and its scopes of names.
final class FunctionContext {
    enum Kind: Equatable {
        case method, initializer, global, closure, getter
    }

    let kind: Kind
    let selfType: TypeDeclaration?
    let isStatic: Bool
    /// A struct's `mutating` method or initializer: `self` can change.
    let mutatesSelf: Bool
    /// What it may do: wait, and throw. A closure whose type isn't known yet may do either, and is
    /// what it does.
    var effects: Effects
    let effectsInferred: Bool
    /// What it returns; a closure's, inferred from its first `return` when it isn't known.
    var result: SwiftType?
    let parent: FunctionContext?
    let frame: Frame
    var scopes: [[String: Binding]] = [[:]]
    /// The locals declared without a value that haven't been given one on every path here.
    var unassigned: Set<Local> = []
    /// An initializer's stored properties that haven't been given a value on every path.
    var unassignedStored: Set<String> = []
    /// How many `do` blocks with a catch-all it's in: what's tried there is handled there.
    var catching = 0
    /// What it did: whether it waited or threw, for a closure whose effects are inferred.
    var awaited = false
    var threw = false
    let name: String
    /// What `self` is, when it's resolved for a type it's used on: `[Int]` for `Collection`'s
    /// method used on an array of `Int`.
    var selfValueType: SwiftType?
    /// The names the body is resolved with: `Element` as `Int`.
    var typeBindings: [String: SwiftType] = [:]
    /// The generic parameters that are fixed in it: its type's and its own, each the type it
    /// stands for here, never one a call in it infers.
    var fixedParameters: Set<String> = []

    /// The generic parameters fixed in it and the functions it's in.
    var fixedParametersInScope: Set<String> { fixedParameters.union(parent?.fixedParametersInScope ?? []) }

    /// The names it and the functions it's in are resolved with.
    var typeBindingsInScope: [String: SwiftType] {
        (parent?.typeBindingsInScope ?? [:]).merging(typeBindings) { _, own in own }
    }

    /// What `self` is in it: a value of its type, or the type for a static member.
    var selfValueTypeInScope: SwiftType? { selfValueType ?? parent?.selfValueTypeInScope }

    init(
        kind: Kind, name: String, selfType: TypeDeclaration?, isStatic: Bool = false, mutatesSelf: Bool = false,
        effects: Effects,
        effectsInferred: Bool = false, result: SwiftType?, parent: FunctionContext?
    ) {
        self.kind = kind
        self.name = name
        self.selfType = selfType
        self.isStatic = isStatic
        self.mutatesSelf = mutatesSelf
        self.effects = effects
        self.effectsInferred = effectsInferred
        self.result = result
        self.parent = parent
        self.frame = Frame(depth: (parent?.frame.depth ?? -1) + 1)
    }

    /// A name declared in it, or in a function it's in.
    func lookup(_ name: String) -> (Binding, depth: Int)? {
        for scope in scopes.reversed() {
            if let binding = scope[name] { return (binding, frame.depth - binding.frameDepth) }
        }
        return parent?.lookup(name).map { ($0.0, frame.depth - $0.0.frameDepth) }
    }

    func declare(_ name: String, type: SwiftType, mutable: Bool) -> Int {
        let slot = frame.slots
        frame.slots += 1
        scopes[scopes.count - 1][name] = Binding(
            name: name, type: type, mutable: mutable, frameDepth: frame.depth, slot: slot)
        return slot
    }

    func withScope<T>(_ body: () -> T) -> T {
        scopes.append([:])
        defer { scopes.removeLast() }
        return body()
    }
}

final class Frame {
    let depth: Int
    var slots = 0

    init(depth: Int) { self.depth = depth }
}

/// A local: its type, whether it's a `var`, and where it is.
struct Binding {
    let name: String
    let type: SwiftType
    let mutable: Bool
    let frameDepth: Int
    let slot: Int
}
