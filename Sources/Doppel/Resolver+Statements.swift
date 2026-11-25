import SwiftSyntax

extension Resolver {
    /// A block's statements, in the scope it's in.
    func statements(_ list: CodeBlockItemListSyntax) -> [Statement] {
        var resolved: [Statement] = []
        for item in list {
            let made: [Statement]
            switch item.item {
            case .decl(let decl): made = declaration(decl)
            case .stmt(let stmt): made = statement(stmt)
            case .expr(let expr): made = expressionStatement(expr)
            }
            let line = lines.location(for: item.positionAfterSkippingLeadingTrivia).line
            resolved += made.map { .at(line: line, $0) }
        }
        return resolved
    }

    /// A block in a scope of its own.
    func block(_ list: CodeBlockItemListSyntax) -> [Statement] {
        context.withScope { statements(list) }
    }

    private func declaration(_ decl: DeclSyntax) -> [Statement] {
        if let variable = decl.as(VariableDeclSyntax.self) { return localVariables(variable) }
        if let function = decl.as(FunctionDeclSyntax.self) { return localFunction(function) }
        report("this declaration isn't supported inside a function", at: decl)
        return []
    }

    /// A function inside a function: a constant of its function's type, made where it's declared,
    /// that reads the locals around it. Its name is known in its own body, to call itself.
    private func localFunction(_ syntax: FunctionDeclSyntax) -> [Statement] {
        let declared = module.function(syntax, owner: nil, file: "")
        let slot = context.declare(declared.name, type: declared.type, mutable: false)
        let functionContext = FunctionContext(
            kind: .global, name: declared.name, selfType: context.selfType, isStatic: context.isStatic,
            mutatesSelf: context.mutatesSelf,
            effects: declared.effects, result: declared.result, parent: context)
        for parameter in declared.parameters {
            _ = functionContext.declare(parameter.name, type: parameter.type, mutable: parameter.isInout)
        }
        let closure = Closure(parameters: declared.parameters.count)
        if let body = syntax.body {
            closure.body = resolveBody(body.statements, context: functionContext, at: syntax)
        } else {
            report("expected '{' in body of function declaration", at: syntax.name)
        }
        closure.slots = functionContext.frame.slots
        return [.declare(slot, Typed(.closure(closure), declared.type))]
    }

    private func localVariables(_ variable: VariableDeclSyntax) -> [Statement] {
        let mutable = variable.bindingSpecifier.tokenKind == .keyword(.var)
        var resolved: [Statement] = []
        for binding in variable.bindings {
            let annotation = binding.typeAnnotation.map { resolveWritten($0.type) }
            var value: Typed?
            if let initializer = binding.initializer {
                guard let typed = expression(initializer.value, expecting: annotation) else {
                    declareUnknown(binding.pattern, mutable: mutable)
                    continue
                }
                value = annotation.flatMap { convert(typed, to: $0, at: initializer.value, as: .binding) } ?? typed
                if annotation == nil, case .void = typed.type, binding.pattern.is(IdentifierPatternSyntax.self) {
                    // A constant of `()` is Swift, with a warning; it's kept as it is.
                }
            }
            switch binding.pattern {
            case let pattern where pattern.is(WildcardPatternSyntax.self):
                if let value { resolved.append(.expression(value)) }
            case let pattern where pattern.is(IdentifierPatternSyntax.self):
                let name = pattern.as(IdentifierPatternSyntax.self)!.identifier.text
                guard let type = value?.type ?? annotation else {
                    report("type annotation missing in pattern", at: pattern)
                    continue
                }
                let slot = context.declare(name, type: type, mutable: mutable)
                if let value {
                    resolved.append(.declare(slot, value))
                } else if mutable, type.isOptional {
                    resolved.append(.declare(slot, Typed(.nil, type)))
                } else {
                    context.unassigned.insert(Local(depth: context.frame.depth, slot: slot))
                    resolved.append(.declare(slot, nil))
                }
            case let pattern where pattern.is(TuplePatternSyntax.self):
                guard let value, case .tuple(let elements, _) = value.type,
                    let tuple = pattern.as(TuplePatternSyntax.self), tuple.elements.count == elements.count
                else {
                    report("cannot destructure this value into a tuple", at: pattern)
                    continue
                }
                let whole = context.declare("$tuple\(context.frame.slots)", type: value.type, mutable: false)
                resolved.append(.declare(whole, value))
                for (index, (element, type)) in zip(tuple.elements, elements).enumerated() {
                    guard let name = element.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { continue }
                    let slot = context.declare(name, type: type, mutable: mutable)
                    resolved.append(
                        .declare(
                            slot, Typed(.element(Typed(.local(Local(depth: 0, slot: whole)), value.type), index), type))
                    )
                }
            default:
                report("this pattern isn't supported in a declaration", at: binding.pattern)
            }
        }
        return resolved
    }

    /// A name whose value couldn't be resolved, declared so that its uses aren't refused again.
    private func declareUnknown(_ pattern: PatternSyntax, mutable: Bool) {
        if let name = pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
            _ = context.declare(name, type: .unresolved, mutable: mutable)
        }
    }

    private func expressionStatement(_ expr: ExprSyntax) -> [Statement] {
        if let ifExpr = expr.as(IfExprSyntax.self) { return [ifStatement(ifExpr)] }
        if let switchExpr = expr.as(SwitchExprSyntax.self) { return [switchStatement(switchExpr)] }
        if let infix = expr.as(InfixOperatorExprSyntax.self), Self.isAssignment(expr) {
            return assignment(infix).map { [$0] } ?? []
        }
        guard let typed = expression(expr, expecting: nil) else { return [] }
        return [.expression(typed)]
    }

    private func statement(_ stmt: StmtSyntax) -> [Statement] {
        if let expressionStatement = stmt.as(ExpressionStmtSyntax.self) {
            return self.expressionStatement(expressionStatement.expression)
        }
        if let guardStmt = stmt.as(GuardStmtSyntax.self) { return [guardStatement(guardStmt)] }
        if let returnStmt = stmt.as(ReturnStmtSyntax.self) { return returnStatement(returnStmt).map { [$0] } ?? [] }
        if let throwStmt = stmt.as(ThrowStmtSyntax.self) { return throwStatement(throwStmt).map { [$0] } ?? [] }
        if let whileStmt = stmt.as(WhileStmtSyntax.self) {
            let before = context.unassigned
            let resolved = context.withScope { () -> Statement in
                let conditions = self.conditions(whileStmt.conditions)
                return .while(conditions, body: block(whileStmt.body.statements))
            }
            context.unassigned = before
            return [resolved]
        }
        if let repeatStmt = stmt.as(RepeatStmtSyntax.self) {
            let body = block(repeatStmt.body.statements)
            guard let condition = booleanCondition(repeatStmt.condition) else { return [] }
            return [.repeatWhile(body: body, condition: condition)]
        }
        if let forStmt = stmt.as(ForStmtSyntax.self) { return forStatement(forStmt).map { [$0] } ?? [] }
        if stmt.is(BreakStmtSyntax.self) { return [.break] }
        if stmt.is(ContinueStmtSyntax.self) { return [.continue] }
        if let deferStmt = stmt.as(DeferStmtSyntax.self) { return [.defer(block(deferStmt.body.statements))] }
        if let doStmt = stmt.as(DoStmtSyntax.self) {
            guard !doStmt.catchClauses.isEmpty else { return [.block(block(doStmt.body.statements))] }
            return [doCatch(doStmt)].compactMap { $0 }
        }
        report("this statement isn't supported", at: stmt)
        return []
    }

    /// `do`-`catch`: a body whose errors are handled when a catch takes any, each catch binding
    /// `error`, or its own pattern.
    private func doCatch(_ doStmt: DoStmtSyntax) -> Statement? {
        let catchesAll = doStmt.catchClauses.contains {
            $0.catchItems.isEmpty
                || $0.catchItems.contains { item in
                    item.whereClause == nil
                        && (item.pattern?.as(ValueBindingPatternSyntax.self)?.pattern.is(IdentifierPatternSyntax.self)
                            ?? false)
                }
        }
        if catchesAll { context.catching += 1 }
        let body = block(doStmt.body.statements)
        if catchesAll { context.catching -= 1 }
        let error = SwiftType.existential(["Error"])
        let errorSlot = context.declare("$error\(context.frame.slots)", type: error, mutable: false)
        var catches: [(pattern: Pattern?, body: [Statement])] = []
        for clause in doStmt.catchClauses {
            let resolved = context.withScope { () -> (pattern: Pattern?, body: [Statement])? in
                var pattern: Pattern?
                if clause.catchItems.isEmpty {
                    pattern = .bind(context.declare("error", type: error, mutable: false))
                } else if clause.catchItems.count == 1, let item = clause.catchItems.first, item.whereClause == nil,
                    let binding = item.pattern?.as(ValueBindingPatternSyntax.self),
                    let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                {
                    pattern = .bind(context.declare(name, type: error, mutable: false))
                } else {
                    report(
                        "this 'catch' pattern isn't supported; catch the error and switch on it",
                        at: clause.catchKeyword)
                    return nil
                }
                return (pattern, statements(clause.body.statements))
            }
            if let resolved { catches.append(resolved) }
        }
        // A catch that doesn't take every error lets the rest through, to the function around it.
        if !catchesAll { markThrows(at: doStmt.doKeyword, thrown: true) }
        return .doCatch(body: body, error: errorSlot, catches: catches)
    }

    // MARK: Conditions

    /// A branch's statements; of an `if` or `switch` that's a value, its one expression, returned.
    private func branch(_ list: CodeBlockItemListSyntax, valued: SwiftType?) -> [Statement] {
        guard let valued, let only = list.first,
            let value = only.item.as(ExprSyntax.self) ?? only.item.as(ExpressionStmtSyntax.self)?.expression
        else { return statements(list) }
        if let nested = value.as(IfExprSyntax.self), Self.isValued(nested) {
            return [ifStatement(nested, valued: valued)]
        }
        if let nested = value.as(SwitchExprSyntax.self), Self.isValued(nested) {
            return [switchStatement(nested, valued: valued)]
        }
        guard let typed = expression(value, expecting: valued),
            let converted = convert(typed, to: valued, at: value, as: .returned)
        else { return [] }
        return [.return(converted)]
    }

    func ifStatement(_ ifExpr: IfExprSyntax, valued: SwiftType? = nil) -> Statement {
        var branches: [(conditions: [Condition], body: [Statement])] = []
        var otherwise: [Statement]?
        let before = context.unassigned
        var after: Set<Local>? = nil
        func merge(_ body: CodeBlockItemListSyntax) {
            guard canFallThrough(body) else { return }
            after = after.map { $0.union(context.unassigned) } ?? context.unassigned
        }
        var current: IfExprSyntax? = ifExpr
        while let branch = current {
            context.unassigned = before
            let resolved = context.withScope { () -> (conditions: [Condition], body: [Statement]) in
                (conditions(branch.conditions), self.branch(branch.body.statements, valued: valued))
            }
            merge(branch.body.statements)
            branches.append(resolved)
            switch branch.elseBody {
            case .ifExpr(let next)?:
                current = next
            case .codeBlock(let block)?:
                context.unassigned = before
                otherwise = context.withScope { self.branch(block.statements, valued: valued) }
                merge(block.statements)
                current = nil
            case nil:
                after = (after ?? before).union(before)
                current = nil
            }
        }
        context.unassigned = after ?? before
        return .if(branches: branches, otherwise: otherwise)
    }

    private func guardStatement(_ guardStmt: GuardStmtSyntax) -> Statement {
        let before = context.unassigned
        let otherwise = block(guardStmt.body.statements)
        if canFallThrough(guardStmt.body.statements) {
            report(
                "'guard' body must not fall through, consider using a 'return' or 'throw' to exit the scope",
                at: guardStmt.guardKeyword)
        }
        context.unassigned = before
        // What it binds is known after it, in the scope it's in.
        return .guard(conditions(guardStmt.conditions), otherwise: otherwise)
    }

    /// Conditions, each in turn: what one binds, the next ones read.
    func conditions(_ list: ConditionElementListSyntax) -> [Condition] {
        list.compactMap { element -> Condition? in
            switch element.condition {
            case .expression(let expr):
                return booleanCondition(expr).map(Condition.boolean)
            case .optionalBinding(let binding):
                return optionalBinding(binding)
            case .matchingPattern(let matching):
                guard let value = expression(matching.initializer.value, expecting: nil) else { return nil }
                guard let pattern = pattern(matching.pattern, matching: value.type) else { return nil }
                return .matches(pattern, value)
            default:
                report("this condition isn't supported", at: element)
                return nil
            }
        }
    }

    func booleanCondition(_ expr: ExprSyntax) -> Typed? {
        guard let typed = expression(expr, expecting: .bool) else { return nil }
        if case .optional = typed.type {
            report("optional type '\(typed.type)' cannot be used as a boolean; test for '!= nil' instead", at: expr)
            return nil
        }
        return convert(typed, to: .bool, at: expr, as: .condition)
    }

    private func optionalBinding(_ binding: OptionalBindingConditionSyntax) -> Condition? {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            report("this pattern isn't supported in a condition", at: binding.pattern)
            return nil
        }
        let annotation = binding.typeAnnotation.map { resolveWritten($0.type) }
        let value: Typed?
        if let initializer = binding.initializer {
            value = expression(initializer.value, expecting: annotation.map(SwiftType.optional))
        } else {
            // `if let name`: the optional of the same name.
            value = reference(name, at: binding.pattern)
        }
        guard let value else { return nil }
        guard case .optional(let wrapped) = value.type else {
            report(
                "initializer for conditional binding must have Optional type, not '\(value.type)'",
                at: Syntax(binding.initializer?.value) ?? Syntax(binding.pattern))
            return nil
        }
        var bound = wrapped
        var source = value
        if let annotation {
            guard let converted = convert(Typed(.chained, wrapped), to: annotation, at: binding, as: .binding) else {
                return nil
            }
            bound = annotation
            if case .chained = converted.expression {
            } else {
                source = Typed(.chain(value, converted), .optional(annotation))
            }
        }
        let mutable = binding.bindingSpecifier.tokenKind == .keyword(.var)
        return .bind(context.declare(name, type: bound, mutable: mutable), source)
    }

    // MARK: Patterns

    /// A pattern a value of `type` is matched with: an enum's case, with patterns for its values; a
    /// value it's equal to; a binding; or anything.
    func pattern(_ syntax: PatternSyntax, matching type: SwiftType, binding: Bool = false, mutable: Bool = false)
        -> Pattern?
    {
        if syntax.is(WildcardPatternSyntax.self) { return .wildcard }
        if let identifier = syntax.as(IdentifierPatternSyntax.self) {
            return .bind(context.declare(identifier.identifier.text, type: type, mutable: mutable))
        }
        if let valueBinding = syntax.as(ValueBindingPatternSyntax.self) {
            return pattern(
                valueBinding.pattern, matching: type, binding: true,
                mutable: valueBinding.bindingSpecifier.tokenKind == .keyword(.var))
        }
        if let tuple = syntax.as(TuplePatternSyntax.self) {
            guard case .tuple(let elements, _) = type, elements.count == tuple.elements.count else {
                report("tuple pattern cannot match values of the non-tuple type '\(type)'", at: syntax)
                return nil
            }
            var patterns: [Pattern] = []
            for (element, elementType) in zip(tuple.elements, elements) {
                guard let resolved = pattern(element.pattern, matching: elementType, binding: binding, mutable: mutable)
                else { return nil }
                patterns.append(resolved)
            }
            return .tuple(patterns)
        }
        if let expressionPattern = syntax.as(ExpressionPatternSyntax.self) {
            return pattern(expressionPattern.expression, matching: type, binding: binding, mutable: mutable)
        }
        report("this pattern isn't supported", at: syntax)
        return nil
    }

    private func pattern(_ expr: ExprSyntax, matching type: SwiftType, binding: Bool, mutable: Bool) -> Pattern? {
        if expr.is(DiscardAssignmentExprSyntax.self) { return .wildcard }
        if let patternExpr = expr.as(PatternExprSyntax.self) {
            return pattern(patternExpr.pattern, matching: type, binding: binding, mutable: mutable)
        }
        if binding, let reference = expr.as(DeclReferenceExprSyntax.self) {
            return .bind(context.declare(reference.baseName.text, type: type, mutable: mutable))
        }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count > 1 {
            guard case .tuple(let elements, _) = type, elements.count == tuple.elements.count else {
                report("tuple pattern cannot match values of the non-tuple type '\(type)'", at: expr)
                return nil
            }
            var patterns: [Pattern] = []
            for (element, elementType) in zip(tuple.elements, elements) {
                guard
                    let resolved = pattern(
                        element.expression, matching: elementType, binding: binding, mutable: mutable)
                else { return nil }
                patterns.append(resolved)
            }
            return .tuple(patterns)
        }
        // `.some(x)`, `.case`, `.case(let value)`, `Type.case`: a case of the value's enum.
        let caseName: String?
        let arguments: LabeledExprListSyntax?
        if let call = expr.as(FunctionCallExprSyntax.self),
            let member = call.calledExpression.as(MemberAccessExprSyntax.self)
        {
            (caseName, arguments) = (member.declName.baseName.text, call.arguments)
        } else if let member = expr.as(MemberAccessExprSyntax.self) {
            (caseName, arguments) = (member.declName.baseName.text, nil)
        } else {
            (caseName, arguments) = (nil, nil)
        }
        if let caseName {
            if case .optional(let wrapped) = type {
                if caseName == "none", arguments == nil { return .value(Typed(.nil, type)) }
                if caseName == "some", let only = arguments?.first, arguments?.count == 1 {
                    return pattern(only.expression, matching: wrapped, binding: binding, mutable: mutable).map(
                        Pattern.some)
                }
                // A case of the optional's value's enum: `.done` for a `Status?`.
                return pattern(expr, matching: wrapped, binding: binding, mutable: mutable).map(Pattern.some)
            }
            if case .named(let name, _) = type, let declaration = module.type(named: name),
                declaration.kind == .enumeration
            {
                guard let enumCase = declaration.case(caseName) else {
                    report("type '\(name)' has no member '\(caseName)'", at: expr)
                    return nil
                }
                guard let arguments else { return .enumCase(caseName, []) }
                guard arguments.count == enumCase.values.count else {
                    report("tuple pattern has the wrong length for tuple type", at: expr)
                    return nil
                }
                var patterns: [Pattern] = []
                // Its values are of the types its enum is of: `Int` for `Success` in a `Result<Int, …>`.
                let bindings = typeBindings(of: type)
                for (argument, value) in zip(arguments, enumCase.values) {
                    guard
                        let resolved = pattern(
                            argument.expression, matching: value.type.substituting(bindings), binding: binding,
                            mutable: mutable)
                    else { return nil }
                    patterns.append(resolved)
                }
                return .enumCase(caseName, patterns)
            }
        }
        if expr.is(NilLiteralExprSyntax.self), type.isOptional { return .value(Typed(.nil, type)) }
        // A value it's equal to.
        guard let value = expression(expr, expecting: type) else { return nil }
        guard let converted = convert(value, to: type, at: expr, as: .argument) else { return nil }
        guard conforms(type, to: "Equatable") else {
            report("operator function '~=' requires that '\(type)' conform to 'Equatable'", at: expr)
            return nil
        }
        return .value(converted)
    }

    // MARK: Switch

    func switchStatement(_ switchExpr: SwitchExprSyntax, valued: SwiftType? = nil) -> Statement {
        guard let subject = expression(switchExpr.subject, expecting: nil) else { return .block([]) }
        let before = context.unassigned
        var after: Set<Local>? = nil
        var cases: [(patterns: [Pattern], guard: Typed?, body: [Statement])] = []
        // The patterns that match whatever else holds: those without a `where`.
        var unguarded: [[Pattern]] = []
        for element in switchExpr.cases {
            guard case .switchCase(let switchCase) = element else {
                report("'#if' in a switch isn't supported", at: element)
                continue
            }
            context.unassigned = before
            let resolved = context.withScope { () -> (patterns: [Pattern], guard: Typed?, body: [Statement]) in
                var patterns: [Pattern] = []
                var guarded: Typed?
                switch switchCase.label {
                case .default:
                    patterns = [.wildcard]
                    unguarded.append([.wildcard])
                case .case(let label):
                    for item in label.caseItems {
                        guard let resolved = pattern(item.pattern, matching: subject.type) else { continue }
                        patterns.append(resolved)
                        if let whereClause = item.whereClause {
                            guarded = booleanCondition(whereClause.condition)
                        } else {
                            unguarded.append([resolved])
                        }
                    }
                }
                return (patterns, guarded, branch(switchCase.statements, valued: valued))
            }
            if canFallThrough(switchCase.statements) {
                after = after.map { $0.union(context.unassigned) } ?? context.unassigned
            }
            cases.append(resolved)
        }
        if !exhausts(unguarded, [subject.type]) {
            report("switch must be exhaustive", at: switchExpr.switchKeyword)
        }
        context.unassigned = after ?? before
        return .switch(subject, cases: cases)
    }

    static func isIrrefutable(_ pattern: Pattern) -> Bool {
        switch pattern {
        case .wildcard, .bind: true
        case .tuple(let patterns): patterns.allSatisfy(isIrrefutable)
        default: false
        }
    }

    /// Whether `rows` of patterns match every value of `types`, as Swift checks a switch: each
    /// type is split into its cases, a `Bool`'s two values, an optional's `nil` and its value, an
    /// enum's cases with their values, and each case is checked in turn with what's in it. A type
    /// of too many values to list is matched only by a pattern that matches any value.
    private func exhausts(_ rows: [[Pattern]], _ types: [SwiftType]) -> Bool {
        guard let first = types.first else { return !rows.isEmpty }
        let rest = Array(types.dropFirst())
        // A tuple is its elements, each in turn.
        if case .tuple(let elements, _) = first {
            let spread = rows.compactMap { row -> [Pattern]? in
                if case .tuple(let patterns) = row[0], patterns.count == elements.count {
                    return patterns + row.dropFirst()
                }
                return Self.isIrrefutable(row[0])
                    ? Array(repeating: .wildcard, count: elements.count) + row.dropFirst() : nil
            }
            return exhausts(spread, elements + rest)
        }
        guard let splits = cases(of: first) else {
            return exhausts(rows.filter { Self.isIrrefutable($0[0]) }.map { Array($0.dropFirst()) }, rest)
        }
        return splits.allSatisfy { split in
            let specialized = rows.compactMap { row -> [Pattern]? in
                let any = Array(repeating: Pattern.wildcard, count: split.values.count)
                if Self.isIrrefutable(row[0]) { return any + row.dropFirst() }
                guard let inner = Self.matched(row[0], by: split.name) else { return nil }
                // `.case` without its values matches whatever it holds.
                return (inner.isEmpty ? any : inner) + row.dropFirst()
            }
            return exhausts(specialized, split.values + rest)
        }
    }

    /// The cases a value of `type` is one of, each with the types of what it holds; `nil` for a
    /// type of too many values to list.
    private func cases(of type: SwiftType) -> [(name: String, values: [SwiftType])]? {
        switch type {
        case .bool: return [("true", []), ("false", [])]
        case .optional(let wrapped): return [("nil", []), ("some", [wrapped])]
        case .named(let name, _):
            guard let declaration = module.type(named: name), declaration.kind == .enumeration else { return nil }
            let bindings = typeBindings(of: type)
            return declaration.cases.map { enumCase in
                (enumCase.name, enumCase.values.map { $0.type.substituting(bindings) })
            }
        default:
            return nil
        }
    }

    /// What `pattern` matches inside the case `name`, when it matches that case at all.
    private static func matched(_ pattern: Pattern, by name: String) -> [Pattern]? {
        switch pattern {
        case .value(let value):
            if case .bool(let literal) = value.expression, "\(literal)" == name { return [] }
            if case .nil = value.expression, name == "nil" { return [] }
            return nil
        case .some(let inner): return name == "some" ? [inner] : nil
        case .enumCase(let caseName, let values): return caseName == name ? values : nil
        default: return nil
        }
    }

    // MARK: Loops, returns and throws

    private func forStatement(_ forStmt: ForStmtSyntax) -> Statement? {
        guard let sequence = expression(forStmt.sequence, expecting: nil) else { return nil }
        if forStmt.awaitKeyword != nil { return forAwaitStatement(forStmt, over: sequence) }
        let element: SwiftType
        switch sequence.type {
        case .array(let type): element = type
        case .named("Set", let arguments) where arguments.count == 1: element = arguments[0]
        case .string: element = .character
        case .dictionary(let key, let value): element = .tuple([key, value], labels: ["key", "value"])
        case .dynamic, .unresolved: element = sequence.type
        default:
            // A library's own sequence: of the elements it names, `UInt8` for `Data`.
            guard let name = sequence.type.declarationName, module.type(named: name)?.kind == .standard,
                conforms(sequence.type, to: "Sequence"), let named = typeBindings(of: sequence.type)["Element"]
            else {
                report("for-in loop requires '\(sequence.type)' to conform to 'Sequence'", at: forStmt.sequence)
                return nil
            }
            element = named
        }
        let before = context.unassigned
        defer { context.unassigned = before }
        return context.withScope { () -> Statement? in
            guard let pattern = pattern(forStmt.pattern, matching: element) else { return nil }
            var body = statements(forStmt.body.statements)
            if let whereClause = forStmt.whereClause, let condition = booleanCondition(whereClause.condition) {
                body = [.if(branches: [([.boolean(condition)], body)], otherwise: nil)]
            }
            return .forIn(pattern, sequence: sequence, body: body)
        }
    }

    /// `for await element in sequence`, as Swift defines it: the sequence's iterator, made once,
    /// asked for its next element until it has none, each waited for, and tried when it can throw.
    ///
    ///     var iterator = sequence.makeAsyncIterator()
    ///     while case let element? = await iterator.next() { … }
    private func forAwaitStatement(_ forStmt: ForStmtSyntax, over sequence: Typed) -> Statement? {
        guard sequence.type != .dynamic, sequence.type != .unresolved, conforms(sequence.type, to: "AsyncSequence"),
            let sequenceName = sequence.type.declarationName, let sequenceType = module.type(named: sequenceName)
        else {
            report("for-in loop requires '\(sequence.type)' to conform to 'AsyncSequence'", at: forStmt.sequence)
            return nil
        }
        if !context.effectsInferred, !context.effects.async, let awaitKeyword = forStmt.awaitKeyword {
            report("'async' in a function that does not support concurrency", at: awaitKeyword)
            return nil
        }
        let none = CallArguments(LabeledExprListSyntax([]), trailing: nil)
        guard
            let makeIterator = methodCall(
                instanceMethods("makeAsyncIterator", of: sequence.type), of: sequenceType, on: sequence,
                place: .expression(forStmt.sequence), arguments: none, expecting: nil, named: "makeAsyncIterator",
                at: forStmt.sequence),
            let iteratorName = makeIterator.type.declarationName, let iteratorType = module.type(named: iteratorName)
        else { return nil }
        let nexts = instanceMethods("next", of: makeIterator.type).filter { $0.parameters.isEmpty }
        if nexts.contains(where: { $0.effects.throwing }), forStmt.tryKeyword == nil {
            report("for-in loop can throw, but is not marked with 'try'", at: forStmt.forKeyword)
            return nil
        }
        let before = context.unassigned
        defer { context.unassigned = before }
        return context.withScope { () -> Statement? in
            let slot = context.declare("$iterator", type: makeIterator.type, mutable: true)
            let iterator = Place.local(Local(depth: 0, slot: slot))
            // The loop's own `try` and `await` mark its calls to `next()`.
            let outer = marks
            marks.awaited = true
            if forStmt.tryKeyword != nil {
                marks.tried = outer.tried == .optional || outer.tried == .forced ? outer.tried : .plain
            }
            let next = methodCall(
                nexts, of: iteratorType, on: Typed(.local(Local(depth: 0, slot: slot)), makeIterator.type),
                place: .place(iterator), arguments: none, expecting: nil, named: "next", at: forStmt.sequence)
            marks = outer
            guard let next, case .optional(let element) = next.type else { return nil }
            guard let pattern = pattern(forStmt.pattern, matching: element) else { return nil }
            var body = statements(forStmt.body.statements)
            if let whereClause = forStmt.whereClause, let condition = booleanCondition(whereClause.condition) {
                body = [.if(branches: [([.boolean(condition)], body)], otherwise: nil)]
            }
            let waited = Typed(.await(next), next.type)
            let asked = forStmt.tryKeyword != nil ? Typed(.try(waited), next.type) : waited
            return .block([.declare(slot, makeIterator), .while([.matches(.some(pattern), asked)], body: body)])
        }
    }

    private func returnStatement(_ returnStmt: ReturnStmtSyntax) -> Statement? {
        guard let value = returnStmt.expression else {
            if let result = context.result, result != .void {
                report("non-void function should return a value", at: returnStmt)
            }
            if context.kind == .closure, context.result == nil { context.result = .void }
            return .return(nil)
        }
        if context.kind == .initializer {
            // A failable initializer's `return nil`: it fails, and makes nothing.
            if value.is(NilLiteralExprSyntax.self) {
                guard context.failable else {
                    report("only a failable initializer can return 'nil'", at: returnStmt)
                    return nil
                }
                return .return(Typed(.nil, .optional(.void)))
            }
            report("'nil' is the only return value permitted in an initializer", at: returnStmt)
            return nil
        }
        guard let typed = expression(value, expecting: context.result) else { return nil }
        guard let result = context.result else {
            context.result = typed.type
            return .return(typed)
        }
        if result == .void, typed.type != .void {
            report("unexpected non-void return value in void function", at: value)
            return nil
        }
        return convert(typed, to: result, at: value, as: .returned).map { .return($0) }
    }

    private func throwStatement(_ throwStmt: ThrowStmtSyntax) -> Statement? {
        guard let value = expression(throwStmt.expression, expecting: nil) else { return nil }
        guard conforms(value.type, to: "Error") else {
            report("thrown expression type '\(value.type)' does not conform to 'Error'", at: throwStmt.expression)
            return nil
        }
        markThrows(at: throwStmt, thrown: true)
        return .throw(Typed(.erase(value), .existential(["Error"])))
    }

    /// Whether the code can run to its end without returning, throwing or leaving its loop.
    func canFallThrough(_ list: CodeBlockItemListSyntax) -> Bool {
        guard let last = list.last else { return true }
        switch last.item {
        case .stmt(let stmt):
            if stmt.is(ReturnStmtSyntax.self) || stmt.is(ThrowStmtSyntax.self) || stmt.is(BreakStmtSyntax.self)
                || stmt.is(ContinueStmtSyntax.self)
            {
                return false
            }
            if let expression = stmt.as(ExpressionStmtSyntax.self)?.expression { return canFallThrough(expression) }
            if let doStmt = stmt.as(DoStmtSyntax.self) { return canFallThrough(doStmt.body.statements) }
            if let whileStmt = stmt.as(WhileStmtSyntax.self), whileStmt.conditions.trimmedDescription == "true" {
                return whileStmt.body.statements.contains { $0.trimmedDescription.hasPrefix("break") }
            }
            return true
        case .expr(let expr):
            return canFallThrough(expr)
        case .decl:
            return true
        }
    }

    private func canFallThrough(_ expr: ExprSyntax) -> Bool {
        if let ifExpr = expr.as(IfExprSyntax.self) {
            guard canFallThrough(ifExpr.body.statements) == false else { return true }
            switch ifExpr.elseBody {
            case .ifExpr(let next)?: return canFallThrough(ExprSyntax(next))
            case .codeBlock(let block)?: return canFallThrough(block.statements)
            case nil: return true
            }
        }
        if let switchExpr = expr.as(SwitchExprSyntax.self) {
            return switchExpr.cases.contains { element in
                guard case .switchCase(let switchCase) = element else { return true }
                return canFallThrough(switchCase.statements)
            }
        }
        if let call = expr.as(FunctionCallExprSyntax.self), call.calledExpression.trimmedDescription == "fatalError" {
            return false
        }
        return true
    }
}
