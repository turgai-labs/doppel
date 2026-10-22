import SwiftSyntax

/// The types a type's code declares and uses, each as other code meets it, by name: an actor's
/// fields and the methods it takes, a struct's fields, an enum's cases, a protocol's requirements,
/// and the protocols each conforms to, every type as Swift resolved it.
public struct Declarations: Sendable, Equatable {
    /// A method's parameter, or an enum case's value.
    public struct Parameter: Sendable, Equatable {
        /// What it's called with: `nil` for `_`.
        public let label: String?
        public let name: String
        public let type: SwiftType
        public let hasDefault: Bool
    }

    /// A method it takes: what it's called with, what it gives back, and whether it waits or throws.
    public struct Method: Sendable, Equatable {
        public let name: String
        public let parameters: [Parameter]
        public let result: SwiftType
        public let effects: Effects
        public let documentation: String?
    }

    /// A struct's or an actor's stored property.
    public struct Field: Sendable, Equatable {
        public let name: String
        public let type: SwiftType
        /// It starts with a value, so a value of the struct may leave it out.
        public let hasDefault: Bool
        public let documentation: String?
    }

    /// An enum's case's raw value, as Swift gives it.
    public enum RawValue: Sendable, Equatable {
        case int(Int)
        case double(Double)
        case string(String)
    }

    /// An enum's case, with the values it carries.
    public struct Case: Sendable, Equatable {
        public let name: String
        public let values: [Parameter]
        public let rawValue: RawValue?
        /// What its `///` comment says; a case's isn't kept yet.
        public let documentation: String?
    }

    /// One type, as other code meets it, with the protocols it conforms to, as declared and as
    /// Swift gives them.
    public enum Declaration: Sendable, Equatable {
        /// What it holds, and its methods others can call: neither private nor static.
        case actor(fields: [Field], methods: [Method], conformances: [String], documentation: String?)
        case structure(fields: [Field], conformances: [String], documentation: String?)
        case enumeration(cases: [Case], conformances: [String], documentation: String?)
        /// What a type conforming to it takes: its methods, as each is required.
        case `protocol`(requirements: [Method], documentation: String?)
    }

    /// Each type, by name: the one asked for, and each its fields' and methods' values are.
    public let types: [String: Declaration]

    public subscript(_ name: String) -> Declaration? { types[name] }
}

extension SwiftCheck {
    /// The declarations of the type `type` that `file` declares and of each type it uses, as its
    /// code resolves against the rest of `files`; `nil` with the problems when it doesn't.
    public static func declarations(of type: String, in file: String, of files: [File]) -> (
        problems: [Diagnostic], declarations: Declarations?
    ) {
        let (problems, program) = resolve(file, of: files)
        guard let program else { return (problems, nil) }
        guard program.type(named: type) != nil else {
            return ([Diagnostic(line: 1, column: 1, message: "'\(file)' declares no type '\(type)'")], nil)
        }
        var reading = DeclarationReading(program: program)
        reading.declare(type)
        return (problems, Declarations(types: reading.declarations))
    }
}

/// Reads the declarations of a type and of the types it uses, once each.
private struct DeclarationReading {
    let program: ResolvedProgram
    var declarations: [String: Declarations.Declaration] = [:]

    mutating func parameter(_ parameter: Parameter) -> Declarations.Parameter {
        Declarations.Parameter(
            label: parameter.label, name: parameter.name, type: read(parameter.type), hasDefault: parameter.hasDefault)
    }

    /// `type`, with each type it names declared.
    mutating func read(_ type: SwiftType) -> SwiftType {
        switch type {
        case .optional(let wrapped), .array(let wrapped), .inout(let wrapped):
            _ = read(wrapped)
        case .dictionary(let key, let value):
            _ = read(key)
            _ = read(value)
        case .tuple(let elements, _):
            for element in elements { _ = read(element) }
        case .named(let name, let arguments):
            for argument in arguments { _ = read(argument) }
            declare(name)
        case .existential(let protocols):
            for name in protocols { declare(name) }
        default:
            break
        }
        return type
    }

    mutating func declare(_ name: String) {
        guard declarations[name] == nil, let declaration = program.type(named: name) else { return }
        let documentation = Self.documentation(of: declaration.syntax.map(Syntax.init))
        let conformances = program.resolver.module.protocols(of: declaration).sorted()
        switch declaration.kind {
        case .actor:
            // Declared before what it holds and takes are read, so a type that names it is read once.
            declarations[name] = .actor(
                fields: [], methods: [], conformances: conformances, documentation: documentation)
            let methods = declaration.methods.values.flatMap { $0 }
                .filter { !$0.isStatic && !$0.isPrivate }
                .sorted { $0.name < $1.name }
                .map { method in
                    Declarations.Method(
                        name: method.name, parameters: method.parameters.map { parameter($0) },
                        result: read(method.result),
                        effects: method.effects, documentation: Self.documentation(of: method.syntax))
                }
            let fields = fields(of: declaration).filter { !$0.isStatic }.map(\.field)
            declarations[name] = .actor(
                fields: fields, methods: methods, conformances: conformances, documentation: documentation)
        case .structure:
            declarations[name] = .structure(fields: [], conformances: conformances, documentation: documentation)
            declarations[name] = .structure(
                fields: fields(of: declaration).map(\.field), conformances: conformances, documentation: documentation)
        case .enumeration:
            declarations[name] = .enumeration(cases: [], conformances: conformances, documentation: documentation)
            let cases = declaration.cases.map { enumCase in
                Declarations.Case(
                    name: enumCase.name, values: enumCase.values.map { parameter($0) },
                    rawValue: program.rawValue(of: declaration, case: enumCase.name).map {
                        switch $0 {
                        case .int(let number): .int(number)
                        case .double(let number): .double(number)
                        case .string(let text): .string(text)
                        }
                    },
                    documentation: nil)
            }
            declarations[name] = .enumeration(cases: cases, conformances: conformances, documentation: documentation)
        case .protocol:
            declarations[name] = .protocol(requirements: [], documentation: documentation)
            let requirements = declaration.requirements
                .sorted { $0.name < $1.name }
                .map { requirement in
                    Declarations.Method(
                        name: requirement.name, parameters: requirement.parameters.map { parameter($0) },
                        result: read(requirement.result),
                        effects: requirement.effects, documentation: Self.documentation(of: requirement.syntax))
                }
            declarations[name] = .protocol(requirements: requirements, documentation: documentation)
        case .standard:
            break
        }
    }

    /// Its stored properties, each with its type read.
    private mutating func fields(of declaration: TypeDeclaration) -> [(field: Declarations.Field, isStatic: Bool)] {
        declaration.stored.indices.map { index in
            let property = declaration.stored[index]
            return (
                Declarations.Field(
                    name: property.name, type: read(program.storedType(of: declaration, at: index)),
                    hasDefault: property.hasValue, documentation: Self.documentation(of: property.syntax)),
                property.isStatic
            )
        }
    }

    /// What a declaration's `///` comment says, its lines joined.
    static func documentation(of syntax: Syntax?) -> String? {
        // A property's syntax is its binding; the comment is on its declaration.
        var declaration = syntax
        while let node = declaration, !node.is(DeclSyntax.self) { declaration = node.parent }
        guard let declaration else { return nil }
        let lines = declaration.leadingTrivia.compactMap { piece -> String? in
            guard case .docLineComment(let text) = piece else { return nil }
            return String(text.dropFirst(3).drop { $0 == " " })
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}
