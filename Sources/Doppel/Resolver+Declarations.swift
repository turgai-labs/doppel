import SwiftSyntax

extension Resolver {
    /// Resolves every declaration of the checked file: its types and their members, its functions,
    /// and its constants.
    func resolveFile() {
        defer {
            // Every value type's and actor's stored properties' starting values, its given files'
            // too: what a value made of one holds.
            for type in module.types.values where [.structure, .actor, .enumeration].contains(type.kind) {
                for property in type.stored { _ = startingValue(of: property, in: type) }
            }
            // Types written anywhere in it that aren't known, its declarations' and its bodies'.
            for problem in module.typeProblems { report(problem.message, at: problem.node) }
        }
        for redeclared in module.redeclared {
            report("invalid redeclaration of '\(redeclared.name)'", at: redeclared.node)
        }
        for statement in checked.statements {
            let item = statement.item
            if let type = module.declares(item), type.kind != .protocol {
                resolveType(type)
            } else if let decl = item.as(ExtensionDeclSyntax.self) {
                guard let type = module.type(named: decl.extendedType.trimmedDescription) else {
                    report("cannot find type '\(decl.extendedType.trimmedDescription)' in scope", at: decl.extendedType)
                    continue
                }
                resolveMembers(of: type, in: decl.memberBlock)
            } else if let decl = item.as(FunctionDeclSyntax.self) {
                if let function = module.functions[decl.name.text]?.first(where: { $0.syntax?.id == decl.id }) {
                    _ = resolvedBody(of: function)
                }
            } else if let decl = item.as(VariableDeclSyntax.self) {
                for binding in decl.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    _ = globalType(name)
                }
            } else if item.is(ImportDeclSyntax.self) || item.is(ProtocolDeclSyntax.self)
                || item.is(TypeAliasDeclSyntax.self)
            {
                continue
            } else if item.is(ExprSyntax.self) || item.is(StmtSyntax.self) {
                report("expressions are not allowed at the top level", at: item)
            }
        }
    }

    // MARK: Types

    func resolveType(_ type: TypeDeclaration) {
        guard let syntax = type.syntax else { return }
        let block: MemberBlockSyntax
        let name: TokenSyntax
        let inheritance: InheritanceClauseSyntax?
        if let decl = syntax.as(ActorDeclSyntax.self) {
            (block, name, inheritance) = (decl.memberBlock, decl.name, decl.inheritanceClause)
        } else if let decl = syntax.as(StructDeclSyntax.self) {
            (block, name, inheritance) = (decl.memberBlock, decl.name, decl.inheritanceClause)
        } else if let decl = syntax.as(EnumDeclSyntax.self) {
            (block, name, inheritance) = (decl.memberBlock, decl.name, decl.inheritanceClause)
        } else {
            return
        }
        for inherited in inheritance?.inheritedTypes ?? [] {
            let written = inherited.type.trimmedDescription
            if module.type(named: written) == nil, !["Int", "String", "Double"].contains(written) {
                report("cannot find type '\(written)' in scope", at: inherited.type)
            }
        }
        // An actor's stored properties all have a value once it's made: each its own, or given by
        // its initializer.
        if type.kind == .actor, type.initializers.allSatisfy(\.isInExtension),
            type.stored.contains(where: { !$0.hasValue })
        {
            report("\(type.kind == .actor ? "actor" : "class") '\(type.name)' has no initializers", at: name)
        }
        checkRedeclarations(in: block)
        checkConformances(of: type, at: name)
        resolveMembers(of: type, in: block)
    }

    private func checkRedeclarations(in block: MemberBlockSyntax) {
        var seen: Set<String> = []
        for member in block.members {
            let key: String
            let node: Syntax
            if let variable = member.decl.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
                let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            {
                (key, node) = ("value \(name)", Syntax(binding.pattern))
            } else if let function = member.decl.as(FunctionDeclSyntax.self) {
                let labels = function.signature.parameterClause.parameters.map {
                    "\($0.firstName.text):\($0.type.trimmedDescription)"
                }
                (key, node) = ("func \(function.name.text)(\(labels.joined(separator: ",")))", Syntax(function.name))
            } else {
                continue
            }
            if !seen.insert(key).inserted {
                let name = key.split(separator: " ", maxSplits: 1)[1].split(separator: "(")[0]
                report("invalid redeclaration of '\(name)'", at: node)
            }
        }
    }

    /// Each protocol it conforms to has each of its requirements met, as an actor's are: a method
    /// of an actor's own state can only meet an `async` requirement, or one of an actor protocol.
    private func checkConformances(of type: TypeDeclaration, at name: TokenSyntax) {
        for conformance in type.conformances.sorted() {
            guard let protocolType = module.type(named: conformance), protocolType.kind == .protocol else { continue }
            // The protocol's associated types, as the type binds them: by its own type aliases first,
            // then as its methods meeting the requirements say, as Swift infers them.
            var bindings = typeBindings(of: type.declaredType).filter { protocolType.associatedTypes.contains($0.key) }
            bindings["Self"] = type.declaredType
            let associated = Set(protocolType.associatedTypes + ["Self"])
            for requirement in protocolType.requirements {
                guard
                    let method = type.methods[requirement.name]?.first(where: {
                        matches($0, requirement, associated: associated, bindings: &bindings)
                    })
                else {
                    report("type '\(type.name)' does not conform to protocol '\(conformance)'", at: name)
                    break
                }
                let isolated = !protocolType.refines.contains("Actor") && conformance != "Actor"
                if type.kind == .actor, isolated, !requirement.effects.async, let syntax = method.syntax {
                    report(
                        "actor-isolated instance method '\(method.written)' cannot be used to satisfy nonisolated requirement from protocol '\(conformance)'",
                        at: syntax.as(FunctionDeclSyntax.self)?.name ?? syntax.firstToken(viewMode: .sourceAccurate)
                            ?? TokenSyntax(.wildcard, presence: .missing))
                }
            }
        }
    }

    /// Whether `method` meets `requirement`, its associated types bound as they're met: one bound
    /// already must be the same, one not yet is what the method has there. A method that doesn't
    /// meet it binds nothing.
    private func matches(
        _ method: Function, _ requirement: Function, associated: Set<String>, bindings: inout [String: SwiftType]
    ) -> Bool {
        guard method.parameters.count == requirement.parameters.count else { return false }
        var tried = bindings
        for (given, required) in zip(method.parameters, requirement.parameters) {
            guard given.label == required.label, infer(required.type, from: given.type, associated, &tried) else {
                return false
            }
        }
        guard infer(requirement.result, from: method.result, associated, &tried) else { return false }
        bindings = tried
        return true
    }

    /// Whether `witness` is `required` with the associated types in it bound, binding those that
    /// aren't yet: `Element?` is `Int?` with `Element` bound to `Int`.
    private func infer(
        _ required: SwiftType, from witness: SwiftType, _ associated: Set<String>, _ bindings: inout [String: SwiftType]
    ) -> Bool {
        switch (required, witness) {
        case (.parameter(let name), _) where associated.contains(name):
            if let bound = bindings[name] { return bound == witness }
            bindings[name] = witness
            return true
        case (.optional(let required), .optional(let witness)), (.array(let required), .array(let witness)),
            (.inout(let required), .inout(let witness)):
            return infer(required, from: witness, associated, &bindings)
        case (.dictionary(let requiredKey, let requiredValue), .dictionary(let key, let value)):
            return infer(requiredKey, from: key, associated, &bindings)
                && infer(requiredValue, from: value, associated, &bindings)
        case (.tuple(let required, let requiredLabels), .tuple(let witness, let labels)):
            return required.count == witness.count && requiredLabels == labels
                && zip(required, witness).allSatisfy { infer($0, from: $1, associated, &bindings) }
        case (.named(let requiredName, let required), .named(let name, let witness)):
            return requiredName == name && required.count == witness.count
                && zip(required, witness).allSatisfy { infer($0, from: $1, associated, &bindings) }
        default:
            return required == witness
        }
    }

    private func resolveMembers(of type: TypeDeclaration, in block: MemberBlockSyntax) {
        for member in block.members {
            let decl = member.decl
            if let function = decl.as(FunctionDeclSyntax.self) {
                if type.kind == .actor, function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) })
                {
                    report(
                        "'mutating' is not valid on instance methods in classes",
                        at: function.modifiers.first { $0.name.tokenKind == .keyword(.mutating) }!)
                }
                guard let declared = type.methods[function.name.text]?.first(where: { $0.syntax?.id == function.id })
                else { continue }
                if function.body == nil {
                    report("expected '{' in body of function declaration", at: function.name)
                    continue
                }
                _ = resolvedBody(of: declared)
            } else if let initializer = decl.as(InitializerDeclSyntax.self) {
                guard let declared = type.initializers.first(where: { $0.syntax?.id == initializer.id }) else {
                    continue
                }
                _ = resolvedBody(of: declared)
            } else if let variable = decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                        let property = type.properties[name]
                    else { continue }
                    _ = propertyType(property, of: type)
                    resolveAccessors(of: property, binding: binding, in: type)
                }
            } else if decl.is(StructDeclSyntax.self) || decl.is(EnumDeclSyntax.self),
                let nested = module.declares(.decl(decl), in: type.name)
            {
                // A type in it is checked as any other is.
                resolveType(nested)
            }
        }
    }

    /// A property's type: as written, or as its starting value is, which is resolved once.
    func propertyType(_ property: Property, of type: TypeDeclaration) -> SwiftType {
        let key = "\(type.name).\(property.name)"
        switch property.typing {
        case .written(let written):
            if let binding = property.syntax?.as(PatternBindingSyntax.self), let value = binding.initializer?.value,
                inferred[key] == nil
            {
                inferred[key] = written
                startingValues[key] = initialValue(value, as: written, of: type)
            }
            return written
        case .inferred(let value):
            if let known = inferred[key] { return known }
            inferred[key] = .unresolved
            let starting = initialValue(value, as: nil, of: type)
            startingValues[key] = starting
            let resolved = starting?.value.type ?? .unresolved
            inferred[key] = resolved
            return resolved
        }
    }

    /// A stored property's starting value, resolved where `self` isn't yet.
    /// A stored property's starting value, resolved where `self` isn't yet, with the locals its
    /// closures need.
    private func initialValue(_ value: ExprSyntax, as type: SwiftType?, of owner: TypeDeclaration) -> StartingValue? {
        let context = FunctionContext(
            kind: .getter, name: "initializer", selfType: nil, effects: .none, result: type, parent: nil)
        let typed: Typed? = within(context) {
            guard let typed = expression(value, expecting: type) else { return nil }
            return type.map { convert(typed, to: $0, at: value, as: .binding) } ?? typed
        }
        return typed.map { StartingValue(value: $0, slots: context.frame.slots) }
    }

    /// The starting value of a type's stored property, if it has one.
    func startingValue(of property: Property, in type: TypeDeclaration) -> StartingValue? {
        _ = propertyType(property, of: type)
        return startingValues["\(type.name).\(property.name)"]
    }

    private func resolveAccessors(of property: Property, binding: PatternBindingSyntax, in type: TypeDeclaration) {
        guard let accessors = binding.accessorBlock else { return }
        let result = propertyType(property, of: type)
        if let getter = property.getter { _ = resolvedBody(of: getter) }
        switch accessors.accessors {
        case .getter:
            break
        case .accessors(let list):
            for accessor in list {
                guard let body = accessor.body else { continue }
                let isGetter = accessor.accessorSpecifier.tokenKind == .keyword(.get)
                if isGetter { continue }
                let context = FunctionContext(
                    kind: .getter, name: property.name, selfType: type, isStatic: property.isStatic,
                    mutatesSelf: !isGetter && [.structure, .enumeration].contains(type.kind),
                    effects: isGetter ? property.effects : .none,
                    result: isGetter ? result : .void, parent: nil)
                if !isGetter {
                    let parameter =
                        accessor.parameters?.name.text
                        ?? (accessor.accessorSpecifier.text == "willSet" ? "newValue" : "oldValue")
                    _ = context.declare(parameter, type: result, mutable: false)
                }
                resolveBody(body.statements, context: context, at: accessor)
            }
        }
    }

    // MARK: Functions

    /// A function's body, resolved once.
    func resolvedBody(of function: Function) -> ResolvedFunction {
        if let resolved = bodies[ObjectIdentifier(function)] { return resolved }
        let resolved = ResolvedFunction(function)
        bodies[ObjectIdentifier(function)] = resolved
        guard let syntax = function.syntax, syntax.root.id == checked.root.id else { return resolved }
        let owner = function.owner.flatMap(module.type(named:))
        let isInitializer = function.name == "init"
        let isGetter = syntax.is(PatternBindingSyntax.self)
        let context = FunctionContext(
            kind: isInitializer ? .initializer : isGetter ? .getter : owner == nil ? .global : .method,
            name: function.name, selfType: owner,
            isStatic: function.isStatic,
            mutatesSelf: [.structure, .enumeration].contains(owner?.kind) && (function.isMutating || isInitializer),
            // A `rethrows` function's body may throw what its closures do.
            effects: function.isRethrowing ? Effects(async: function.effects.async, throwing: true) : function.effects,
            result: isInitializer ? .void : function.result, parent: nil)
        context.fixedParameters = Set((owner?.generics ?? []) + function.generics)
        for parameter in function.parameters {
            _ = context.declare(parameter.name, type: parameter.type, mutable: parameter.isInout)
        }
        if isInitializer, let owner {
            context.unassignedStored = Set(owner.stored.filter { !$0.hasValue }.map(\.name))
        }
        let body =
            syntax.as(FunctionDeclSyntax.self)?.body?.statements ?? syntax.as(InitializerDeclSyntax.self)?.body?
            .statements
            ?? Self.getterStatements(syntax.as(PatternBindingSyntax.self))
        if let body {
            resolved.body = resolveBody(body, context: context, at: syntax)
        }
        resolved.slots = context.frame.slots
        return resolved
    }

    /// A body's statements, resolved in `context`: one of a single expression returns it, and one
    /// that can end without returning returns nothing, which only a function returning nothing can.
    @discardableResult
    func resolveBody(_ statements: CodeBlockItemListSyntax, context: FunctionContext, at node: some SyntaxProtocol)
        -> [Statement]
    {
        within(context) {
            let result = context.result ?? .void
            // A body that's one `if` or `switch` whose branches are each one expression returns
            // the branch's value, as Swift 5.9 has it.
            if result != .void, statements.count == 1, let only = statements.first,
                let branching = Self.branchingValue(only)
            {
                if let ifExpr = branching.as(IfExprSyntax.self), Self.isValued(ifExpr) {
                    return [ifStatement(ifExpr, valued: result)]
                }
                if let switchExpr = branching.as(SwitchExprSyntax.self), Self.isValued(switchExpr) {
                    return [switchStatement(switchExpr, valued: result)]
                }
            }
            if statements.count == 1, let only = statements.first, let value = only.item.as(ExprSyntax.self),
                result != .void, !value.is(AssignmentExprSyntax.self), !Self.isAssignment(value)
            {
                guard let typed = expression(value, expecting: result) else { return [] }
                return convert(typed, to: result, at: value, as: .returned).map { [.return($0)] } ?? []
            }
            let resolved = self.statements(statements)
            // A body cut short by a syntax problem isn't checked for how it ends.
            let complete =
                !(statements.parent?.as(CodeBlockSyntax.self)?.rightBrace.presence == .missing)
                && !(statements.parent?.as(AccessorBlockSyntax.self)?.rightBrace.presence == .missing)
            guard complete else { return resolved }
            if result != .void, result != .never, canFallThrough(statements) {
                report(
                    "missing return in \(context.missingReturnSubject) expected to return '\(result)'",
                    at: statements.lastToken(viewMode: .sourceAccurate) ?? node.lastToken(viewMode: .sourceAccurate)!)
            }
            if context.kind == .initializer, !context.unassignedStored.isEmpty, canFallThrough(statements) {
                report(
                    "return from initializer without initializing all stored properties",
                    at: statements.lastToken(viewMode: .sourceAccurate) ?? node.lastToken(viewMode: .sourceAccurate)!)
            }
            return resolved
        }
    }

    /// An `if` or `switch` a body is made of.
    static func branchingValue(_ item: CodeBlockItemSyntax) -> ExprSyntax? {
        let expression = item.item.as(ExprSyntax.self) ?? item.item.as(ExpressionStmtSyntax.self)?.expression
        guard let expression, expression.is(IfExprSyntax.self) || expression.is(SwitchExprSyntax.self) else {
            return nil
        }
        return expression
    }

    /// Whether each branch is one expression, and there's an `else`: a value.
    static func isValued(_ ifExpr: IfExprSyntax) -> Bool {
        guard isOneExpression(ifExpr.body.statements) else { return false }
        switch ifExpr.elseBody {
        case .ifExpr(let next)?: return isValued(next)
        case .codeBlock(let block)?: return isOneExpression(block.statements)
        case nil: return false
        }
    }

    static func isValued(_ switchExpr: SwitchExprSyntax) -> Bool {
        switchExpr.cases.allSatisfy { element in
            guard case .switchCase(let switchCase) = element else { return false }
            return isOneExpression(switchCase.statements)
        }
    }

    static func isOneExpression(_ statements: CodeBlockItemListSyntax) -> Bool {
        guard statements.count == 1, let only = statements.first else { return false }
        if let value = only.item.as(ExprSyntax.self) { return !isAssignment(value) }
        return only.item.as(ExpressionStmtSyntax.self).map { !isAssignment($0.expression) } ?? false
    }

    /// A computed property's getter's statements.
    static func getterStatements(_ binding: PatternBindingSyntax?) -> CodeBlockItemListSyntax? {
        switch binding?.accessorBlock?.accessors {
        case .getter(let statements)?: statements
        case .accessors(let list)?: list.first { $0.accessorSpecifier.tokenKind == .keyword(.get) }?.body?.statements
        default: nil
        }
    }

    static func isAssignment(_ expression: ExprSyntax) -> Bool {
        guard let infix = expression.as(InfixOperatorExprSyntax.self) else { return false }
        if infix.operator.is(AssignmentExprSyntax.self) { return true }
        if let op = infix.operator.as(BinaryOperatorExprSyntax.self), op.operator.text.hasSuffix("="),
            !["==", "!=", "<=", ">=", "==="].contains(op.operator.text)
        {
            return true
        }
        return false
    }

    /// `body` run with `context` as the function being resolved.
    func within<T>(_ context: FunctionContext, _ body: () -> T) -> T {
        let (outer, outerMarks) = (self.context, marks)
        self.context = context
        marks = Marks()
        defer { (self.context, marks) = (outer, outerMarks) }
        return body()
    }

    /// A global constant's type, resolved from its value once.
    func globalType(_ name: String) -> SwiftType? {
        guard var global = module.globals[name] else { return nil }
        if let type = global.type { return type }
        global.type = .unresolved
        module.globals[name] = global
        let typed = global.initializer.flatMap { value in
            within(FunctionContext(kind: .global, name: name, selfType: nil, effects: .none, result: nil, parent: nil))
            {
                expression(value, expecting: nil)
            }
        }
        global.type = typed?.type ?? .unresolved
        module.globals[name] = global
        if let typed { resolved.globals.append((name, typed)) }
        return global.type
    }
}

extension FunctionContext {
    /// What Swift calls it, when it's missing a `return`.
    var missingReturnSubject: String {
        switch kind {
        case .method: isStatic ? "static method" : "instance method"
        case .global: "global function"
        case .closure: "closure"
        case .getter: "getter"
        case .initializer: "initializer"
        }
    }
}
