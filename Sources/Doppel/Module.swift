import SwiftParser
import SwiftSyntax

/// What a module declares, across its files and the standard library: its types with their
/// members, its typealiases, and its global functions and constants.
final class Module {
    private(set) var types: [String: TypeDeclaration] = [:]
    private(set) var aliases: [String: TypeSyntax] = [:]
    private(set) var functions: [String: [Function]] = [:]
    /// Global constants and variables, typed once their initializers are.
    var globals: [String: GlobalBinding] = [:]

    /// A global `let` or `var`: its type when it's written, or the value it's given.
    struct GlobalBinding {
        let name: String
        let mutable: Bool
        let annotation: TypeSyntax?
        let initializer: ExprSyntax?
        var type: SwiftType?
        let file: String
    }

    /// A type declared twice: the declaration that came second, which isn't used.
    private(set) var redeclared: [(node: Syntax, name: String)] = []

    /// The modules each file imports.
    private var imports: [String: Set<String>] = [:]

    /// Whether `file` can name the type `name`: Foundation's only when its module imports
    /// Foundation, in any of its files, as an object's module does for the types it's given.
    func names(_ name: String, in file: String) -> Bool {
        !FoundationLibrary.typeNames.contains(name) || file == FoundationLibrary.file
            || imports.values.contains { !$0.isDisjoint(with: FoundationLibrary.modules) }
    }

    /// Where a type is written that isn't known, for the file it's in.
    private(set) var typeProblems: [(file: String, node: Syntax, message: String)] = []

    /// A type written where it's not known, as Swift says it.
    private func unknown(_ name: String, at node: some SyntaxProtocol, in file: String) {
        typeProblems.append((file, Syntax(node), "cannot find type '\(name)' in scope"))
    }

    init(files: [(name: String, syntax: SourceFileSyntax)]) {
        let all =
            [("<standard library>", StandardLibrary.syntax), (FoundationLibrary.file, FoundationLibrary.syntax)] + files
        for (file, syntax) in files {
            imports[file] = Set(
                syntax.statements.compactMap { $0.item.as(ImportDeclSyntax.self)?.path.first?.name.text })
        }
        // Every type's name first, so each can be used in any other's, in any order.
        for (file, syntax) in all {
            for statement in syntax.statements { declareType(statement.item, file: file) }
        }
        for (file, syntax) in all {
            for statement in syntax.statements { declareMembers(statement.item, file: file) }
        }
        for type in types.values where type.kind == .enumeration && type.cases.allSatisfy(\.values.isEmpty) {
            type.conformances.formUnion(["Equatable", "Hashable"])
        }
    }

    func type(named name: String) -> TypeDeclaration? { types[name] }

    /// Every protocol a type conforms to: those it declares, then those they refine, nearest first.
    func protocols(of declaration: TypeDeclaration) -> [String] {
        var found: [String] = []
        var next = declaration.kind == .protocol ? [declaration.name] : declaration.conformances.sorted()
        while !next.isEmpty {
            let name = next.removeFirst()
            guard !found.contains(name) else { continue }
            found.append(name)
            next += (types[name]?.refines ?? []).sorted()
        }
        return found
    }

    // MARK: Declarations

    /// Declares the type `item` declares, inside `outer` when it's nested: named with the types
    /// it's in, `Outer.Inner`, as Swift names it.
    private func declareType(_ item: CodeBlockItemSyntax.Item, file: String, in outer: String? = nil) {
        let standard = file == "<standard library>" || file == FoundationLibrary.file
        // An extension's types are the extended type's, as if declared in it.
        if let extended = item.as(ExtensionDeclSyntax.self) {
            for member in extended.memberBlock.members
            where member.decl.is(StructDeclSyntax.self) || member.decl.is(EnumDeclSyntax.self) {
                declareType(.decl(member.decl), file: file, in: extended.extendedType.trimmedDescription)
            }
            return
        }
        guard let name = Self.declaredName(item, in: outer) else { return }
        if types[name] != nil || aliases[name] != nil {
            redeclared.append((Syntax(item), name))
            return
        }
        // A type nested in a generic type has that type's generic parameters, then its own: Swift's
        // `AsyncStream<Int>.Continuation` is a continuation of `Int`s.
        let outerGenerics = outer.flatMap { types[$0] }.map { $0.kind == .protocol ? [] : $0.generics } ?? []
        if let decl = item.as(StructDeclSyntax.self) {
            types[name] = TypeDeclaration(
                name: name, kind: standard ? .standard : .structure,
                generics: outerGenerics + Self.generics(decl.genericParameterClause),
                file: file, syntax: DeclSyntax(decl))
        } else if let decl = item.as(EnumDeclSyntax.self) {
            types[name] = TypeDeclaration(
                name: name, kind: .enumeration, generics: outerGenerics + Self.generics(decl.genericParameterClause),
                file: file, syntax: DeclSyntax(decl))
        } else if let decl = item.as(ActorDeclSyntax.self) {
            types[name] = TypeDeclaration(name: name, kind: .actor, file: file, syntax: DeclSyntax(decl))
        } else if let decl = item.as(ProtocolDeclSyntax.self) {
            types[name] = TypeDeclaration(name: name, kind: .protocol, file: file, syntax: DeclSyntax(decl))
        } else if let decl = item.as(TypeAliasDeclSyntax.self) {
            aliases[name] = decl.initializer.value
        }
        // Its own types are declared with it, before any members are read: Swift names a type
        // wherever it's declared, so a field can be of a type declared after it.
        if let members = Self.memberBlock(item) {
            for member in members.members {
                if let nested = member.decl.as(StructDeclSyntax.self) {
                    declareType(.decl(DeclSyntax(nested)), file: file, in: name)
                } else if let nested = member.decl.as(EnumDeclSyntax.self) {
                    declareType(.decl(DeclSyntax(nested)), file: file, in: name)
                } else if let nested = member.decl.as(ProtocolDeclSyntax.self) {
                    // A protocol nested in a type, as Swift 5.10 allows (SE-0404).
                    declareType(.decl(DeclSyntax(nested)), file: file, in: name)
                }
            }
        }
    }

    /// The members of a struct, enum or actor declaration.
    private static func memberBlock(_ item: CodeBlockItemSyntax.Item) -> MemberBlockSyntax? {
        if let decl = item.as(StructDeclSyntax.self) { return decl.memberBlock }
        if let decl = item.as(EnumDeclSyntax.self) { return decl.memberBlock }
        if let decl = item.as(ActorDeclSyntax.self) { return decl.memberBlock }
        return nil
    }

    /// The name a type declaration declares, inside `outer` when it's nested: `Outer.Inner`.
    static func declaredName(_ item: CodeBlockItemSyntax.Item, in outer: String? = nil) -> String? {
        let name: String
        if let decl = item.as(StructDeclSyntax.self) {
            name = decl.name.text
        } else if let decl = item.as(EnumDeclSyntax.self) {
            name = decl.name.text
        } else if let decl = item.as(ActorDeclSyntax.self) {
            name = decl.name.text
        } else if let decl = item.as(ProtocolDeclSyntax.self) {
            name = decl.name.text
        } else if let decl = item.as(TypeAliasDeclSyntax.self) {
            name = decl.name.text
        } else {
            return nil
        }
        return outer.map { "\($0).\(name)" } ?? name
    }

    /// The declaration a type's members are read from, inside `outer` when it's nested: the one
    /// its name was first declared by.
    func declares(_ item: CodeBlockItemSyntax.Item, in outer: String? = nil) -> TypeDeclaration? {
        guard let name = Self.declaredName(item, in: outer), let type = types[name],
            type.syntax?.id == item.as(DeclSyntax.self)?.id
        else {
            return nil
        }
        return type
    }

    /// The type `name` names where it's written, inside the type `scope`: a type nested in it
    /// first, then in each type it's in, then the module's, as Swift looks a name up.
    func lookup(_ name: String, in scope: String?) -> String? {
        var outer = scope
        while let current = outer {
            if types["\(current).\(name)"] != nil { return "\(current).\(name)" }
            outer = current.lastIndex(of: ".").map { String(current[..<$0]) }
        }
        return types[name] != nil ? name : nil
    }

    private func declareMembers(_ item: CodeBlockItemSyntax.Item, file: String, in outer: String? = nil) {
        if let decl = item.as(StructDeclSyntax.self), let type = declares(item, in: outer) {
            members(
                of: type, decl.memberBlock, inheritance: decl.inheritanceClause, file: file,
                constraints: ownRequirements(of: type, file: file))
        } else if let decl = item.as(EnumDeclSyntax.self), let type = declares(item, in: outer) {
            members(
                of: type, decl.memberBlock, inheritance: decl.inheritanceClause, file: file,
                constraints: ownRequirements(of: type, file: file))
        } else if let decl = item.as(ActorDeclSyntax.self), let type = declares(item, in: outer) {
            type.conformances.insert("Actor")
            members(of: type, decl.memberBlock, inheritance: decl.inheritanceClause, file: file)
        } else if let decl = item.as(ProtocolDeclSyntax.self), let type = declares(item, in: outer) {
            for inherited in decl.inheritanceClause?.inheritedTypes ?? [] {
                type.refines.insert(inherited.type.trimmedDescription)
            }
            // Its associated types, and those of what it refines, name types in it and its
            // extensions, as `Self` does: each is bound by the type conforming.
            type.associatedTypes = decl.memberBlock.members.compactMap {
                $0.decl.as(AssociatedTypeDeclSyntax.self)?.name.text
            }
            let inherited = type.refines.flatMap { types[$0]?.generics ?? [] }
            type.generics = Array(Set(["Self"] + inherited + type.associatedTypes)).sorted()
            // Its requirements are what its extensions are written with: members of it.
            for member in decl.memberBlock.members {
                if let function = member.decl.as(FunctionDeclSyntax.self) {
                    let requirement = self.function(function, owner: type, file: file)
                    type.requirements.append(requirement)
                    type.methods[requirement.name, default: []].append(requirement)
                } else if let variable = member.decl.as(VariableDeclSyntax.self) {
                    for property in properties(variable, owner: type, file: file) {
                        type.properties[property.name] = property
                    }
                }
            }
        } else if let decl = item.as(ExtensionDeclSyntax.self), let type = types[decl.extendedType.trimmedDescription] {
            // What the extension's `where` asks of the type, each of its members asks too.
            let constraints =
                ownRequirements(of: type, file: file)
                + requirements(nil, decl.genericWhereClause, generics: type.generics, file: file)
            members(
                of: type, decl.memberBlock, inheritance: decl.inheritanceClause, file: file, constraints: constraints)
        } else if let decl = item.as(FunctionDeclSyntax.self) {
            functions[decl.name.text, default: []].append(function(decl, owner: nil, file: file))
        } else if let decl = item.as(VariableDeclSyntax.self) {
            let mutable = decl.bindingSpecifier.tokenKind == .keyword(.var)
            for binding in decl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                globals[name] = GlobalBinding(
                    name: name, mutable: mutable, annotation: binding.typeAnnotation?.type,
                    initializer: binding.initializer?.value,
                    type: binding.typeAnnotation.map { resolve($0.type, generics: [], file: file) }, file: file)
            }
        }
    }

    private func members(
        of type: TypeDeclaration, _ block: MemberBlockSyntax, inheritance: InheritanceClauseSyntax?, file: String,
        constraints: [Requirement] = []
    ) {
        for inherited in inheritance?.inheritedTypes ?? [] {
            let name = inherited.type.trimmedDescription
            if type.kind == .enumeration, ["Int", "String", "Double"].contains(name) {
                type.rawType = resolve(inherited.type, generics: [], file: file)
                type.conformances.formUnion(["Equatable", "Hashable"])
            } else {
                type.conformances.insert(name)
                type.conformances.formUnion(types[name]?.refines ?? [])
            }
        }
        for member in block.members {
            let decl = member.decl
            if let variable = decl.as(VariableDeclSyntax.self) {
                for property in properties(variable, owner: type, file: file, constraints: constraints) {
                    type.properties[property.name] = property
                    if property.isStored, !property.isStatic { type.stored.append(property) }
                }
            } else if let function = decl.as(FunctionDeclSyntax.self) {
                type.methods[function.name.text, default: []].append(
                    self.function(function, owner: type, file: file, constraints: constraints))
            } else if let initializer = decl.as(InitializerDeclSyntax.self) {
                type.initializers.append(
                    self.initializer(initializer, owner: type, file: file, constraints: constraints))
            } else if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
                let generics = type.generics
                let parameters = subscriptDecl.parameterClause.parameters.map {
                    parameter($0, generics: generics, file: file, scope: type.name, isSubscript: true)
                }
                let result = resolve(subscriptDecl.returnClause.type, generics: generics, file: file, scope: type.name)
                type.methods["subscript", default: []].append(
                    Function(
                        name: "subscript", parameters: parameters, result: result, effects: .none, owner: type.name,
                        syntax: Syntax(subscriptDecl)))
            } else if let caseDecl = decl.as(EnumCaseDeclSyntax.self) {
                for element in caseDecl.elements {
                    let values =
                        element.parameterClause?.parameters.map { value in
                            Parameter(
                                label: value.firstName?.text == "_" ? nil : value.firstName?.text,
                                name: value.firstName?.text ?? "",
                                type: resolve(value.type, generics: type.generics, file: file, scope: type.name),
                                hasDefault: value.defaultValue != nil,
                                isVariadic: false, isInout: false, defaultValue: value.defaultValue?.value)
                        } ?? []
                    type.cases.append(
                        EnumCase(name: element.name.text, values: values, rawValue: element.rawValue?.value))
                }
            } else if let alias = decl.as(TypeAliasDeclSyntax.self) {
                // A standard type's or protocol's names are its own: `Element` is each collection's.
                if type.kind == .standard || type.kind == .protocol {
                    type.typeAliases[alias.name.text] = (alias.initializer.value, file)
                } else {
                    aliases[alias.name.text] = alias.initializer.value
                }
            } else if let nested = decl.as(StructDeclSyntax.self) {
                // Declared with the type it's in; its members are read here, as that type's are.
                declareMembers(.decl(DeclSyntax(nested)), file: file, in: type.name)
            } else if let nested = decl.as(EnumDeclSyntax.self) {
                declareMembers(.decl(DeclSyntax(nested)), file: file, in: type.name)
            } else if let nested = decl.as(ProtocolDeclSyntax.self) {
                declareMembers(.decl(DeclSyntax(nested)), file: file, in: type.name)
            }
        }
    }

    private func properties(
        _ variable: VariableDeclSyntax, owner: TypeDeclaration, file: String, constraints: [Requirement] = []
    ) -> [Property] {
        let mutable = variable.bindingSpecifier.tokenKind == .keyword(.var)
        let isStatic = variable.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
        return variable.bindings.compactMap { binding -> Property? in
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return nil }
            var effects = Effects.none
            var isStored = true
            if let accessors = binding.accessorBlock {
                switch accessors.accessors {
                case .getter:
                    isStored = false
                case .accessors(let list):
                    let observers = list.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
                    isStored = observers
                    if let getter = list.first(where: { $0.accessorSpecifier.tokenKind == .keyword(.get) }) {
                        effects = Effects(
                            async: getter.effectSpecifiers?.asyncSpecifier != nil,
                            throwing: getter.effectSpecifiers?.throwsClause != nil)
                    }
                }
            }
            // A property's type, as written; one without is its value's, typed where it's resolved.
            let type = binding.typeAnnotation.map {
                resolve($0.type, generics: owner.generics, file: file, scope: owner.name)
            }
            let typing: Property.Typing
            if let type {
                typing = .written(type)
            } else if let value = binding.initializer?.value {
                typing = .inferred(from: value)
            } else {
                // `var x` without a type or a value isn't Swift; the parser said so.
                typing = .written(.any)
            }
            let getter =
                isStored
                ? nil
                : Function(
                    name: name, parameters: [], result: type ?? .any, effects: effects, isStatic: isStatic,
                    owner: owner.name,
                    syntax: Syntax(binding), requirements: constraints)
            var property = Property(
                name: name, typing: typing, mutable: mutable && isStored || !isStored && Self.hasSetter(binding),
                isStored: isStored, isStatic: isStatic,
                hasValue: binding.initializer != nil || (type?.isOptional == true && mutable),
                effects: effects, syntax: Syntax(binding), getter: getter)
            property.isNonmutatingSet = Self.hasNonmutatingSetter(binding)
            return property
        }
    }

    private static func hasNonmutatingSetter(_ binding: PatternBindingSyntax) -> Bool {
        guard case .accessors(let list)? = binding.accessorBlock?.accessors else { return false }
        return list.contains {
            $0.accessorSpecifier.tokenKind == .keyword(.set) && $0.modifier?.name.tokenKind == .keyword(.nonmutating)
        }
    }

    private static func hasSetter(_ binding: PatternBindingSyntax) -> Bool {
        guard case .accessors(let list)? = binding.accessorBlock?.accessors else { return false }
        return list.contains { $0.accessorSpecifier.tokenKind == .keyword(.set) }
    }

    func function(_ decl: FunctionDeclSyntax, owner: TypeDeclaration?, file: String, constraints: [Requirement] = [])
        -> Function
    {
        let generics = (owner?.generics ?? []) + Self.generics(decl.genericParameterClause)
        let effects = decl.signature.effectSpecifiers
        return Function(
            name: decl.name.text,
            parameters: decl.signature.parameterClause.parameters.map {
                parameter($0, generics: generics, file: file, scope: owner?.name)
            },
            result: decl.signature.returnClause.map {
                resolve($0.type, generics: generics, file: file, scope: owner?.name)
            } ?? .void,
            effects: Effects(
                async: effects?.asyncSpecifier != nil,
                throwing: effects?.throwsClause?.throwsSpecifier.tokenKind == .keyword(.throws)),
            isRethrowing: effects?.throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows),
            generics: Self.generics(decl.genericParameterClause),
            isMutating: decl.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) },
            isStatic: decl.modifiers.contains { $0.name.tokenKind == .keyword(.static) },
            isPrivate: decl.modifiers.contains {
                [.keyword(.private), .keyword(.fileprivate)].contains($0.name.tokenKind)
            },
            owner: owner?.name, syntax: Syntax(decl),
            requirements: constraints
                + requirements(decl.genericParameterClause, decl.genericWhereClause, generics: generics, file: file))
    }

    private func initializer(
        _ decl: InitializerDeclSyntax, owner: TypeDeclaration, file: String, constraints: [Requirement] = []
    ) -> Function {
        let effects = decl.signature.effectSpecifiers
        let result: SwiftType = decl.optionalMark != nil ? .optional(owner.declaredType) : owner.declaredType
        let generics = owner.generics + Self.generics(decl.genericParameterClause)
        return Function(
            name: "init",
            parameters: decl.signature.parameterClause.parameters.map {
                parameter($0, generics: generics, file: file, scope: owner.name)
            },
            result: result,
            effects: Effects(
                async: effects?.asyncSpecifier != nil,
                throwing: effects?.throwsClause?.throwsSpecifier.tokenKind == .keyword(.throws)),
            isRethrowing: effects?.throwsClause?.throwsSpecifier.tokenKind == .keyword(.rethrows),
            generics: Self.generics(decl.genericParameterClause),
            owner: owner.name, syntax: Syntax(decl),
            requirements: constraints
                + requirements(decl.genericParameterClause, decl.genericWhereClause, generics: generics, file: file))
    }

    private func parameter(
        _ syntax: FunctionParameterSyntax, generics: [String], file: String, scope: String?, isSubscript: Bool = false
    ) -> Parameter {
        let first = syntax.firstName.text
        // A subscript's parameters, unlike a function's, have no label unless given a second name.
        let label: String? =
            isSubscript ? (syntax.secondName == nil ? nil : (first == "_" ? nil : first)) : (first == "_" ? nil : first)
        var type = syntax.type
        var isInout = false
        if let attributed = type.as(AttributedTypeSyntax.self) {
            isInout = attributed.specifiers.contains { $0.trimmedDescription == "inout" }
            type = attributed.baseType
        }
        let resolved = resolve(type, generics: generics, file: file, scope: scope)
        return Parameter(
            label: label, name: (syntax.secondName ?? syntax.firstName).text,
            type: syntax.ellipsis != nil ? .array(resolved) : resolved,
            hasDefault: syntax.defaultValue != nil, isVariadic: syntax.ellipsis != nil, isInout: isInout,
            defaultValue: syntax.defaultValue?.value)
    }

    /// What a generic type asks of its parameters, which each of its members can rely on:
    /// `Failure: Error` in `Result<Success, Failure: Error>`.
    private func ownRequirements(of type: TypeDeclaration, file: String) -> [Requirement] {
        let clause =
            type.syntax?.as(StructDeclSyntax.self)?.genericParameterClause
            ?? type.syntax?.as(EnumDeclSyntax.self)?.genericParameterClause
        let whereClause =
            type.syntax?.as(StructDeclSyntax.self)?.genericWhereClause
            ?? type.syntax?.as(EnumDeclSyntax.self)?.genericWhereClause
        return requirements(clause, whereClause, generics: type.generics, file: file)
    }

    private func requirements(
        _ clause: GenericParameterClauseSyntax?, _ whereClause: GenericWhereClauseSyntax?, generics: [String],
        file: String
    ) -> [Requirement] {
        var requirements: [Requirement] = []
        for parameter in clause?.parameters ?? [] {
            if let inherited = parameter.inheritedType {
                requirements.append(.conforms(parameter.name.text, to: inherited.trimmedDescription))
            }
        }
        for requirement in whereClause?.requirements ?? [] {
            switch requirement.requirement {
            case .conformanceRequirement(let conformance):
                requirements.append(
                    .conforms(conformance.leftType.trimmedDescription, to: conformance.rightType.trimmedDescription))
            case .sameTypeRequirement(let same):
                guard case .type(let right) = same.rightType else { continue }
                requirements.append(
                    .same(same.leftType.trimmedDescription, as: resolve(right, generics: generics, file: file)))
            default:
                break
            }
        }
        return requirements
    }

    static func generics(_ clause: GenericParameterClauseSyntax?) -> [String] {
        clause?.parameters.map(\.name.text) ?? []
    }

    // MARK: Types

    /// The type `syntax` writes, with `generics` its open parameters. A name that isn't known is
    /// recorded, for the file it's in, and from then on is a type that takes anything, so its
    /// values aren't refused again: Swift says it once.
    /// The type `syntax` writes, inside the type `scope` when it's written in one: a name is
    /// looked up from there outward.
    func resolve(_ syntax: TypeSyntax, generics: [String], file: String, scope: String? = nil) -> SwiftType {
        if let optional = syntax.as(OptionalTypeSyntax.self) {
            return .optional(resolve(optional.wrappedType, generics: generics, file: file, scope: scope))
        }
        if let unwrapped = syntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return .optional(resolve(unwrapped.wrappedType, generics: generics, file: file, scope: scope))
        }
        if let array = syntax.as(ArrayTypeSyntax.self) {
            return .array(resolve(array.element, generics: generics, file: file, scope: scope))
        }
        if let dictionary = syntax.as(DictionaryTypeSyntax.self) {
            return .dictionary(
                key: resolve(dictionary.key, generics: generics, file: file, scope: scope),
                value: resolve(dictionary.value, generics: generics, file: file, scope: scope))
        }
        if let tuple = syntax.as(TupleTypeSyntax.self) {
            let elements = tuple.elements.map { resolve($0.type, generics: generics, file: file, scope: scope) }
            let labels = tuple.elements.map { element in element.firstName.flatMap { $0.text == "_" ? nil : $0.text } }
            return elements.count == 1 && labels[0] == nil
                ? elements[0] : elements.isEmpty ? .void : .tuple(elements, labels: labels)
        }
        if let function = syntax.as(FunctionTypeSyntax.self) {
            return .function(
                parameters: function.parameters.map { parameter in
                    if let attributed = parameter.type.as(AttributedTypeSyntax.self),
                        attributed.specifiers.contains(where: { $0.trimmedDescription == "inout" })
                    {
                        return .inout(resolve(attributed.baseType, generics: generics, file: file, scope: scope))
                    }
                    return resolve(parameter.type, generics: generics, file: file, scope: scope)
                },
                result: resolve(function.returnClause.type, generics: generics, file: file, scope: scope),
                effects: Effects(
                    async: function.effectSpecifiers?.asyncSpecifier != nil,
                    throwing: function.effectSpecifiers?.throwsClause != nil))
        }
        if let attributed = syntax.as(AttributedTypeSyntax.self) {
            return resolve(attributed.baseType, generics: generics, file: file, scope: scope)
        }
        if let metatype = syntax.as(MetatypeTypeSyntax.self), metatype.metatypeSpecifier.text == "Type" {
            return .metatype(resolve(metatype.baseType, generics: generics, file: file, scope: scope))
        }
        if let existential = syntax.as(SomeOrAnyTypeSyntax.self) {
            return .existential(protocols(in: existential.constraint, scope: scope))
        }
        if let composition = syntax.as(CompositionTypeSyntax.self) {
            return .existential(protocols(in: TypeSyntax(composition), scope: scope))
        }
        if let member = syntax.as(MemberTypeSyntax.self) {
            // A type nested in a generic one, named through it: `AsyncStream<Int>.Continuation` has
            // the base's arguments, then its own.
            if let base = member.baseType.as(IdentifierTypeSyntax.self), base.genericArgumentClause != nil,
                case .named(let outer, let outerArguments) = resolve(
                    member.baseType, generics: generics, file: file, scope: scope),
                let nested = types["\(outer).\(member.name.text)"]
            {
                let own =
                    member.genericArgumentClause?.arguments.compactMap { argument -> SwiftType? in
                        guard case .type(let type) = argument.argument else { return nil }
                        return resolve(type, generics: generics, file: file, scope: scope)
                    } ?? []
                return nested.kind == .protocol
                    ? .existential([nested.name]) : .named(nested.name, arguments: outerArguments + own)
            }
            if generics.contains(member.baseType.trimmedDescription) {
                return .parameter("\(member.baseType.trimmedDescription).\(member.name.text)")
            }
            // A nested type, named with what it's in: that's looked up where it's written. One nested
            // in a generic type, named where that type's parameters are in scope, has them.
            let outer = lookup(member.baseType.trimmedDescription, in: scope) ?? member.baseType.trimmedDescription
            if let nested = types["\(outer).\(member.name.text)"] {
                if nested.kind == .protocol { return .existential([nested.name]) }
                let inherited = nested.generics.filter(generics.contains)
                let arguments =
                    inherited.count == nested.generics.count ? inherited.map { SwiftType.parameter($0) } : []
                return .named(nested.name, arguments: arguments)
            }
            // A type has only the types it declares: `Outer.Name` isn't `Name` when `Outer` is a type.
            // Anything else before the dot is a module, as in `Swift.Int`.
            if let declaration = types[outer] {
                typeProblems.append(
                    (
                        file, Syntax(member.name),
                        "'\(member.name.text)' is not a member type of \(declaration.kind.written) '\(outer)'"
                    ))
                return .unresolved
            }
            return resolve(
                TypeSyntax(
                    IdentifierTypeSyntax(name: member.name, genericArgumentClause: member.genericArgumentClause)),
                generics: generics, file: file, scope: scope)
        }
        guard let identifier = syntax.as(IdentifierTypeSyntax.self) else {
            unknown(syntax.trimmedDescription, at: syntax, in: file)
            return .unresolved
        }
        let name = identifier.name.text
        let arguments =
            identifier.genericArgumentClause?.arguments.compactMap { argument -> SwiftType? in
                guard case .type(let type) = argument.argument else { return nil }
                return resolve(type, generics: generics, file: file, scope: scope)
            } ?? []
        if generics.contains(name) { return .parameter(name) }
        switch name {
        case "Int": return .int
        case "Double": return .double
        case "Bool": return .bool
        case "String": return .string
        case "Character": return .character
        case let name where FixedInteger(rawValue: name) != nil: return .fixedInteger(FixedInteger(rawValue: name)!)
        case "Void": return .void
        case "Never": return .never
        case "Any": return .any
        case "Array" where arguments.count == 1: return .array(arguments[0])
        case "Optional" where arguments.count == 1: return .optional(arguments[0])
        case "Dictionary" where arguments.count == 2: return .dictionary(key: arguments[0], value: arguments[1])
        default: break
        }
        guard names(name, in: file) else {
            unknown(name, at: identifier, in: file)
            return .unresolved
        }
        if let alias = aliases[name] { return resolve(alias, generics: generics, file: file, scope: scope) }
        if let found = lookup(name, in: scope), let declared = types[found] {
            if declared.kind == .protocol { return .existential([found]) }
            // A type nested in a generic one, named without its outer type's arguments where those
            // parameters are in scope: they're its own, as in `Continuation` inside `AsyncStream`.
            if arguments.count < declared.generics.count {
                let inherited = declared.generics.prefix(declared.generics.count - arguments.count)
                if inherited.allSatisfy(generics.contains) {
                    return .named(found, arguments: inherited.map { .parameter($0) } + arguments)
                }
            }
            return .named(found, arguments: arguments)
        }
        unknown(name, at: identifier, in: file)
        return .unresolved
    }

    /// The protocols `syntax` names, each as it's looked up where it's written, in `scope`: a
    /// protocol nested in a type is named with that type.
    private func protocols(in syntax: TypeSyntax, scope: String?) -> [String] {
        let elements = syntax.as(CompositionTypeSyntax.self)?.elements.map(\.type) ?? [syntax]
        return elements.map { element in
            if let member = element.as(MemberTypeSyntax.self) {
                let outer = lookup(member.baseType.trimmedDescription, in: scope) ?? member.baseType.trimmedDescription
                let nested = "\(outer).\(member.name.text)"
                return types[nested] != nil ? nested : element.trimmedDescription
            }
            return lookup(element.trimmedDescription, in: scope) ?? element.trimmedDescription
        }
    }
}

extension StandardLibrary {
    /// Its Swift, its operators folded by precedence, as every file's are.
    static let syntax: SourceFileSyntax = SwiftCheck.folded(Parser.parse(source: source))
}
