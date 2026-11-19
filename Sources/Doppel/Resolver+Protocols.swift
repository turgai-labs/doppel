import SwiftSyntax

// A type's members through its protocols, as Swift finds them: its own, then those each protocol it
// conforms to gives in extensions, nearest first. A protocol's extension is Swift, written once:
// its methods are resolved for each type they're used on, with that type's `Self`, associated
// types and generic arguments, as the type conforming binds them.

extension Resolver {
    /// What a value of `type` names: its generic arguments, the types its declaration names
    /// (`Element`, `Index`, `SubSequence`), and `Self`.
    func typeBindings(of type: SwiftType) -> [String: SwiftType] {
        var bindings = type.genericBindings
        bindings["Self"] = type
        guard let name = type.declarationName, let declaration = module.type(named: name) else { return bindings }
        // A declared generic type's arguments: `Element` for `Set<Character>`.
        if case .named(_, let arguments) = type, arguments.count == declaration.generics.count {
            for (parameter, argument) in zip(declaration.generics, arguments) { bindings[parameter] = argument }
        }
        // A name may be written with another: `SubSequence = [Element]`.
        for _ in 0..<2 {
            for (alias, (syntax, file)) in declaration.typeAliases {
                bindings[alias] = module.resolve(
                    syntax, generics: declaration.generics + Array(bindings.keys), file: file
                )
                .substituting(bindings)
            }
        }
        return bindings
    }

    /// The protocols a value of `type` conforms to, as declared, nearest first.
    func protocols(of type: SwiftType) -> [TypeDeclaration] {
        guard let name = type.declarationName, let declaration = module.type(named: name) else { return [] }
        return module.protocols(of: declaration).compactMap(module.type(named:)).filter { $0.kind == .protocol }
    }

    /// A value's instance methods named `name`: its type's own, then those its protocols'
    /// extensions write.
    func instanceMethods(_ name: String, of type: SwiftType) -> [Function] {
        guard let declarationName = type.declarationName, let declaration = module.type(named: declarationName) else {
            return []
        }
        let own = (declaration.methods[name] ?? []).filter { !$0.isStatic }
        let given = protocols(of: type).flatMap { ($0.methods[name] ?? []).filter { !$0.isStatic && isGiven($0) } }
        return own + given
    }

    /// Whether a protocol's member is one its extensions give the types conforming: written in
    /// Swift, or the standard library's own, rather than a requirement they meet themselves.
    func isGiven(_ function: Function) -> Bool {
        guard !Self.isRequirement(function) else { return false }
        return Self.hasBody(function) || isStandard(function)
    }

    /// Whether it's declared in a protocol's body: what the type conforming has of its own.
    static func isRequirement(_ function: Function) -> Bool {
        var node = function.syntax?.parent
        while let current = node {
            if current.is(ProtocolDeclSyntax.self) { return true }
            if current.is(ExtensionDeclSyntax.self) { return false }
            node = current.parent
        }
        return false
    }

    /// A type's static properties and methods, and its initializers, through its protocols too:
    /// those the standard library's extensions give, such as `max` and `init(truncatingIfNeeded:)`,
    /// as members of the type itself.
    func staticProperty(_ name: String, of declaration: TypeDeclaration) -> (Property, TypeDeclaration)? {
        if let own = declaration.properties[name], own.isStatic { return (own, declaration) }
        for conformed in protocols(of: declaration.declaredType) {
            if let property = conformed.properties[name], property.isStatic, let getter = property.getter,
                isGiven(getter)
            {
                return (property, conformed)
            }
        }
        return nil
    }

    func staticMethods(_ name: String, of declaration: TypeDeclaration) -> [Function] {
        (declaration.methods[name] ?? []).filter(\.isStatic)
            + protocols(of: declaration.declaredType).flatMap {
                ($0.methods[name] ?? []).filter { $0.isStatic && isGiven($0) }
            }
    }

    /// A type's initializers: its own, then those its protocols' extensions give, each making a
    /// value of the type itself.
    func initializers(of declaration: TypeDeclaration) -> [Function] {
        let given = protocols(of: declaration.declaredType).flatMap { $0.initializers.filter(isGiven) }.map {
            function in
            Function(
                name: function.name, parameters: function.parameters,
                result: function.result.isOptional ? .optional(declaration.declaredType) : declaration.declaredType,
                effects: function.effects, isRethrowing: function.isRethrowing, generics: function.generics,
                owner: function.owner,
                syntax: function.syntax, requirements: function.requirements)
        }
        return declaration.initializers + given
    }

    /// A value's instance property named `name`, with the type declaring it: its type's own, or
    /// one its protocols' extensions write.
    func instanceProperty(_ name: String, of type: SwiftType) -> (Property, TypeDeclaration)? {
        guard let declarationName = type.declarationName, let declaration = module.type(named: declarationName) else {
            return nil
        }
        if let own = declaration.properties[name] { return (own, declaration) }
        for conformed in protocols(of: type) {
            if let property = conformed.properties[name], !property.isStatic, let getter = property.getter,
                isGiven(getter), satisfies(getter, for: type)
            {
                return (property, conformed)
            }
        }
        return nil
    }

    /// Bindings with each bound generic parameter's associated types too: `S.Element` once `S` is
    /// `[Track]`.
    func withAssociated(_ bindings: [String: SwiftType]) -> [String: SwiftType] {
        var result = bindings
        for (name, type) in bindings where !name.contains(".") && name != "Self" && !type.isOpen {
            for (associated, value) in typeBindings(of: type)
            where associated != "Self" && result["\(name).\(associated)"] == nil {
                result["\(name).\(associated)"] = value
            }
        }
        return result
    }

    /// Whether a member's constraints hold for `type`: `where Element: Equatable`.
    func satisfies(_ function: Function, for type: SwiftType) -> Bool {
        let bindings = typeBindings(of: type)
        return function.requirements.allSatisfy { requirement in
            switch requirement {
            case .conforms(let parameter, let protocolName):
                guard let bound = bound(parameter, in: bindings) else { return true }
                return conforms(bound, to: protocolName)
            case .same(let parameter, let type):
                guard let bound = bound(parameter, in: bindings) else { return true }
                let other = type.substituting(bindings)
                return other.isOpen || bound == other
            }
        }
    }

    /// Whether a function's `where` holds with `bindings`.
    func satisfies(_ function: Function, with bindings: [String: SwiftType]) -> Bool {
        function.requirements.allSatisfy { requirement in
            switch requirement {
            case .conforms(let parameter, let protocolName):
                guard let bound = bound(parameter, in: bindings) else { return true }
                return conforms(bound, to: protocolName)
            case .same(let parameter, let type):
                guard let bound = bound(parameter, in: bindings) else { return true }
                let other = type.substituting(bindings)
                return other.isOpen || bound == other
            }
        }
    }

    /// What a requirement's parameter is bound to: `Element`, or `S.Element`, the associated type
    /// of what `S` is.
    func bound(_ parameter: String, in bindings: [String: SwiftType]) -> SwiftType? {
        let parts = parameter.split(separator: ".").map(String.init)
        guard var type = bindings[parts[0]] else { return nil }
        for part in parts.dropFirst() {
            guard let next = typeBindings(of: type)[part] else { return nil }
            type = next
        }
        return type.isOpen ? nil : type
    }

    /// What a declaration marked `@available(*, unavailable, message:)` says when it's used:
    /// Swift's own refusal, as the standard library declares it.
    static func unavailable(_ function: Function) -> String? {
        let attributes =
            function.syntax?.as(FunctionDeclSyntax.self)?.attributes ?? function.syntax?.as(SubscriptDeclSyntax.self)?
            .attributes
            ?? function.syntax?.as(InitializerDeclSyntax.self)?.attributes
        for case .attribute(let attribute) in attributes ?? []
        where attribute.attributeName.trimmedDescription == "available" {
            guard case .availability(let arguments)? = attribute.arguments,
                arguments.contains(where: { $0.argument.trimmedDescription == "unavailable" })
            else { continue }
            let message = arguments.compactMap { argument -> String? in
                guard case .availabilityLabeledArgument(let labeled) = argument.argument,
                    labeled.label.text == "message",
                    case .string(let text) = labeled.value
                else { return nil }
                return text.segments.trimmedDescription
            }.first
            return "'\(function.written)' is unavailable" + (message.map { ": \($0)" } ?? "")
        }
        return nil
    }

    /// Whether a function, initializer or getter is written with a body, rather than only
    /// declared, as the standard library's own members, which the interpreter runs, are.
    static func hasBody(_ function: Function) -> Bool {
        guard let syntax = function.syntax else { return false }
        if let decl = syntax.as(FunctionDeclSyntax.self) { return decl.body != nil }
        if let decl = syntax.as(InitializerDeclSyntax.self) { return decl.body != nil }
        if let decl = syntax.as(SubscriptDeclSyntax.self) { return getterStatements(decl.accessorBlock) != nil }
        if let binding = syntax.as(PatternBindingSyntax.self) {
            switch binding.accessorBlock?.accessors {
            case .getter?: return true
            case .accessors(let list)?:
                return list.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) && $0.body != nil }
            case nil: return false
            }
        }
        return false
    }

    /// Whether a member is the standard library's, run by the interpreter itself.
    func isNative(_ function: Function) -> Bool {
        isStandard(function) && !Self.hasBody(function)
    }

    /// A type as written in a body: with the names it's resolved for, `Element` as `Character`.
    func resolveWritten(_ syntax: TypeSyntax) -> SwiftType {
        let bindings = context?.typeBindingsInScope ?? [:]
        return module.resolve(syntax, generics: Array(bindings.keys), file: "", scope: context?.selfType?.name)
            .substituting(bindings)
    }

    /// The standard library's function written in Swift, resolved for a value of `type`: its
    /// types bound as `type` binds them, and `self` that value.
    func resolvedBody(of function: Function, for type: SwiftType, generics: [String: SwiftType] = [:])
        -> ResolvedFunction
    {
        // The function's own generic parameters, as the call binds them: `S` in `append(contentsOf:)`.
        let own = generics.filter { function.generics.contains($0.key) }
        let key =
            "\(ObjectIdentifier(function).hashValue) \(type) \(own.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })"
        if let resolved = specialized[key] { return resolved }
        let resolved = ResolvedFunction(function)
        specialized[key] = resolved
        guard let syntax = function.syntax else { return resolved }
        let bindings = withAssociated(typeBindings(of: type).merging(own) { _, call in call })
        let owner = type.declarationName.flatMap(module.type(named:))
        let isInitializer = function.name == "init"
        let isGetter = syntax.is(PatternBindingSyntax.self)
        let context = FunctionContext(
            kind: isInitializer ? .initializer : isGetter ? .getter : owner == nil ? .global : .method,
            name: function.name, selfType: owner,
            isStatic: function.isStatic, mutatesSelf: function.isMutating || isInitializer,
            effects: function.isRethrowing ? Effects(async: function.effects.async, throwing: true) : function.effects,
            result: isInitializer ? .void : function.result.substituting(bindings), parent: nil)
        context.selfValueType = type
        context.typeBindings = bindings
        context.fixedParameters = Set((owner?.generics ?? []) + function.generics)
        // An initializer gives each stored property its value, as one in the file does.
        if isInitializer, let owner {
            context.unassignedStored = Set(owner.stored.filter { !$0.hasValue }.map(\.name))
        }
        for parameter in function.parameters {
            _ = context.declare(parameter.name, type: parameter.type.substituting(bindings), mutable: parameter.isInout)
        }
        let body =
            syntax.as(FunctionDeclSyntax.self)?.body?.statements ?? syntax.as(InitializerDeclSyntax.self)?.body?
            .statements
            ?? Self.getterStatements(syntax.as(PatternBindingSyntax.self)?.accessorBlock)
            ?? Self.getterStatements(syntax.as(SubscriptDeclSyntax.self)?.accessorBlock)
        if let body { resolved.body = resolveBody(body, context: context, at: syntax) }
        resolved.slots = context.frame.slots
        return resolved
    }
}
