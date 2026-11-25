public import SwiftSyntax

/// A type a module declares: a struct, enum, actor or protocol, or one of the standard library's,
/// with its members, as its declaration and its extensions give them.
package final class TypeDeclaration {
    package enum Kind: Equatable {
        case structure, enumeration, actor, `protocol`
        /// A type of the standard library's: its values are the interpreter's own.
        case standard

        /// As Swift names the kind in a diagnostic: `struct`, `enum`, `actor`, `protocol`.
        var written: String {
            switch self {
            case .structure, .standard: "struct"
            case .enumeration: "enum"
            case .actor: "actor"
            case .protocol: "protocol"
            }
        }
    }

    package let name: String
    package let kind: Kind
    /// Its generic parameters: `Element` for `Array`.
    package var generics: [String]
    /// The protocols it conforms to, as declared, and as Swift gives them: an enum without values
    /// is `Equatable` and `Hashable`.
    package var conformances: Set<String> = []
    /// Its stored properties, in order: what a value of it holds.
    package var stored: [Property] = []
    package var properties: [String: Property] = [:]
    package var methods: [String: [Function]] = [:]
    package var initializers: [Function] = []
    /// Its cases, in order, for an enum.
    package var cases: [EnumCase] = []
    package var rawType: SwiftType?
    /// The file it's declared in, and where.
    package let file: String?
    package let syntax: DeclSyntax?
    /// A protocol's requirements.
    package var requirements: [Function] = []
    /// A protocol it refines, such as `Actor`.
    package var refines: Set<String> = []
    /// A protocol's associated types: `Element` for `Sequence`.
    package var associatedTypes: [String] = []
    /// The types it names inside it: `typealias Element = Character` in an extension of `String`.
    package var typeAliases: [String: (syntax: TypeSyntax, file: String)] = [:]

    package init(name: String, kind: Kind, generics: [String] = [], file: String? = nil, syntax: DeclSyntax? = nil) {
        self.name = name
        self.kind = kind
        self.generics = generics
        self.file = file
        self.syntax = syntax
    }

    package func `case`(_ name: String) -> EnumCase? { cases.first { $0.name == name } }

    /// What its declaration's type is, with its generic parameters open.
    package var declaredType: SwiftType {
        switch name {
        case "Int": .int
        case "Double": .double
        case "Bool": .bool
        case "String": .string
        case "Character": .character
        case let name where FixedInteger(rawValue: name) != nil: .fixedInteger(FixedInteger(rawValue: name)!)
        case "Array": .array(.parameter("Element"))
        case "Optional": .optional(.parameter("Wrapped"))
        case "Dictionary": .dictionary(key: .parameter("Key"), value: .parameter("Value"))
        default: .named(name, arguments: generics.map(SwiftType.parameter))
        }
    }
}

/// A property: stored, or computed with what its getter does.
package struct Property {
    /// Where a property's type comes from: written, or its starting value's.
    package enum Typing {
        case written(SwiftType)
        case inferred(from: ExprSyntax)
    }

    package let name: String
    package let typing: Typing
    /// `var`, not `let`.
    package let mutable: Bool
    package let isStored: Bool
    package let isStatic: Bool
    /// A stored property with a starting value.
    package let hasValue: Bool
    /// A computed property's getter's effects: `{ get async throws }`.
    package let effects: Effects
    package let syntax: Syntax?
    /// A computed property's getter, as a function taking nothing.
    package let getter: Function?
    /// Whether it's set without changing the value it's on, `{ get nonmutating set }`: set even on
    /// a constant, as a continuation's `onTermination` is.
    package var isNonmutatingSet = false
}

/// A function, method or initializer, as declared.
package final class Function {
    /// Whether it's declared in an extension rather than its type's own body: such an initializer
    /// leaves the type the one Swift gives it when its body declares none.
    package var isInExtension: Bool {
        var node = syntax?.parent
        while let current = node {
            if current.is(ExtensionDeclSyntax.self) { return true }
            if current.is(StructDeclSyntax.self) || current.is(ActorDeclSyntax.self) || current.is(ClassDeclSyntax.self)
                || current.is(EnumDeclSyntax.self)
            {
                return false
            }
            node = current.parent
        }
        return false
    }

    package let name: String
    package let parameters: [Parameter]
    package let result: SwiftType
    package let effects: Effects
    /// It throws only what its closures throw.
    package let isRethrowing: Bool
    package let generics: [String]
    package let isMutating: Bool
    package let isStatic: Bool
    package let isPrivate: Bool
    /// The type it's a member of, if any.
    package let owner: String?
    package let syntax: Syntax?
    /// What its generic parameters must be: `where Element: Equatable`, `where Element == String`.
    package let requirements: [Requirement]

    /// A failable initializer, `init?`, as it's written: it makes an optional, `nil` when it fails.
    package var isFailable: Bool { syntax?.as(InitializerDeclSyntax.self)?.optionalMark != nil }

    package init(
        name: String, parameters: [Parameter], result: SwiftType, effects: Effects, isRethrowing: Bool = false,
        generics: [String] = [],
        isMutating: Bool = false, isStatic: Bool = false, isPrivate: Bool = false, owner: String?, syntax: Syntax?,
        requirements: [Requirement] = []
    ) {
        self.name = name
        self.parameters = parameters
        self.result = result
        self.effects = effects
        self.isRethrowing = isRethrowing
        self.generics = generics
        self.isMutating = isMutating
        self.isStatic = isStatic
        self.isPrivate = isPrivate
        self.owner = owner
        self.syntax = syntax
        self.requirements = requirements
    }

    /// Its name after the type it's a member of, if it's one's: `Tools.Web.fetch`.
    package var qualifiedName: String { owner.map { "\($0).\(name)" } ?? name }

    /// How it's written to be called: `insert(_:at:)`.
    package var written: String { "\(name)(\(parameters.map { "\($0.label ?? "_"):" }.joined()))" }

    package var type: SwiftType { .function(parameters: parameters.map(\.type), result: result, effects: effects) }
}

/// What a generic parameter must be.
package enum Requirement {
    case conforms(String, to: String)
    case same(String, as: SwiftType)
}

/// A function's parameter.
package struct Parameter {
    /// What it's called with: `nil` for `_`.
    package let label: String?
    package let name: String
    package let type: SwiftType
    package let hasDefault: Bool
    package let isVariadic: Bool
    package let isInout: Bool
    package let defaultValue: ExprSyntax?
}

/// An enum's case, with the values it carries.
package struct EnumCase {
    package let name: String
    package let values: [Parameter]
    package let rawValue: ExprSyntax?
}

/// A function or constant declared at the top of a file: `let mediaControl = MediaControl()`.
package struct Global {
    package let name: String
    package let type: SwiftType
    package let syntax: Syntax
}
