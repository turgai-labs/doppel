public import Doppel

/// A file's actor, live: made from its code, given messages, its state read and set. Everything
/// the files it's given declare is the host's. It runs on whoever owns it, one message at a time,
/// interleaving only where its code waits, as a Swift actor does.
public final class LiveActor {
    /// What's wrong with a file, as Swift would say it: it doesn't run until there's nothing.
    public struct Problems: Error, Sendable, CustomStringConvertible {
        public let diagnostics: [SwiftCheck.Diagnostic]

        public var description: String { diagnostics.map(\.description).joined(separator: "\n") }
    }

    private let evaluator: Evaluator
    private let declaration: TypeDeclaration
    private let instance: ActorInstance

    /// The actor `type` that `file` declares, made with its `init()`, its file resolved against
    /// the rest of `files` first: all of them the module named `module`.
    /// The actor `type` that `file` declares, made with its initializer taking `arguments`, each
    /// matched to its parameter by label: the one actor that runs here. Every other actor its code
    /// makes is another object, the host's.
    public init(
        type: String, in file: String, of files: [SwiftCheck.File], module: String,
        arguments: [(label: String?, value: Portable)] = [],
        host: any ActorHost
    ) async throws {
        let (evaluator, declaration) = try Self.resolve(type, in: file, of: files, module: module, host: host)
        let labels = arguments.map(\.label)
        let chosen = declaration.initializers.first { $0.parameters.map(\.label) == labels }
        guard chosen != nil || arguments.isEmpty else {
            throw Trap(message: "'\(type)' has no init(\(labels.map { "\($0 ?? "_"):" }.joined()))")
        }
        var values: [Value] = []
        for (parameter, argument) in zip(chosen?.parameters ?? [], arguments) {
            values.append(try evaluator.value(argument.value, as: parameter.type, at: ValuePath(named: parameter.name)))
        }
        guard
            case .actor(let instance) = try await evaluator.make(
                type, chosen.map(evaluator.program.body(of:)), values, itself: true)
        else {
            throw Trap(message: "'\(type)' wasn't made")
        }
        self.evaluator = evaluator
        self.declaration = declaration
        self.instance = instance
    }

    private static func resolve(
        _ type: String, in file: String, of files: [SwiftCheck.File], module: String, host: any ActorHost
    ) throws -> (Evaluator, TypeDeclaration) {
        let (problems, program) = SwiftCheck.resolve(file, of: files)
        guard let program else { throw Problems(diagnostics: problems) }
        guard let declaration = program.type(named: type), declaration.isActor,
            program.isOwn(declaration.declarationSyntax)
        else {
            throw Problems(diagnostics: [
                SwiftCheck.Diagnostic(line: 1, column: 1, message: "'\(file)' declares no actor '\(type)'")
            ])
        }
        return (Evaluator(program: program, host: host, module: module), declaration)
    }

    /// Its method `name`, called with `arguments`, each matched to its parameter by label and read
    /// as its type, or left out, `nil`, for its default; its result as `Codable` writes it.
    public func call(_ name: String, arguments: [(label: String?, value: Portable?)]) async throws -> Portable {
        let candidates = declaration.method(name).filter { !$0.isStatic && !$0.isPrivate }
        guard
            let method = candidates.first(where: { $0.parameters.map(\.label) == arguments.map(\.label) })
                ?? candidates.first,
            method.parameters.count == arguments.count
        else {
            throw Trap(
                message:
                    "'\(declaration.name)' takes no '\(name)' with \(arguments.map { "\($0.label ?? "_"):" }.joined())")
        }
        var values: [Value] = []
        for (parameter, argument) in zip(method.parameters, arguments) {
            guard let given = argument.value else {
                // Left out: its default, as Swift takes it for a call that leaves it out.
                guard let value = evaluator.program.defaultValue(of: parameter) else {
                    throw Trap(message: "`\(parameter.name)` has no default to leave it out for")
                }
                values.append(
                    try await evaluator.evaluate(
                        value.value, in: Frame(slots: value.slots, parent: nil, selfValue: nil)))
                continue
            }
            values.append(try evaluator.value(given, as: parameter.type, at: ValuePath(named: parameter.name)))
        }
        let result = try await evaluator.run(
            evaluator.program.body(of: method), on: .actor(instance), arguments: values)
        return try evaluator.portable(result, as: method.result)
    }

    /// What it holds: each stored property, as `Codable` writes it.
    public func fields() throws -> [(name: String, value: Portable)] {
        try declaration.storedNames.enumerated().map { index, name in
            (name, try evaluator.portable(instance.fields[index], as: evaluator.fieldType(declaration, index)))
        }
    }

    /// One of its stored properties given a value, read as its type: what it held before it started again.
    public func set(_ name: String, to value: Portable) throws {
        guard let index = declaration.storedNames.firstIndex(of: name) else {
            throw Trap(message: "'\(declaration.name)' holds no '\(name)'")
        }
        instance.fields[index] = try evaluator.value(
            value, as: evaluator.fieldType(declaration, index), at: ValuePath(named: name))
    }

    /// The `Task { … }` its code started as `id`, run.
    public func runTask(_ id: Int) async throws {
        try await evaluator.runTask(id)
    }
}
