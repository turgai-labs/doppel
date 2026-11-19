import SwiftParser
import SwiftSyntax

extension Resolver {
    /// An expression, resolved and typed, `expected` being what where it's written takes, as Swift
    /// infers from it: a literal's type, an implicit member's, a closure's. What it resolves to
    /// needn't be `expected`: whoever takes it converts it. `nil`, having said why, when it doesn't
    /// resolve.
    func expression(_ expr: ExprSyntax, expecting expected: SwiftType?) -> Typed? {
        // An optional chain: the rest of it reads its base's value, when it has one.
        // A type as a value, `String?.self` among them, which isn't an optional chain.
        if let member = expr.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "self",
            let base = member.base, let type = writtenType(base)
        {
            return Typed(.metatype(type), .metatype(type))
        }
        if !expr.is(OptionalChainingExprSyntax.self), let chain = Self.chain(in: expr), chains[chain.id] == nil {
            guard let base = expression(chain.expression, expecting: nil) else { return nil }
            if base.type == .unresolved { return Typed(.read(base, ""), .unresolved) }
            guard case .optional(let wrapped) = base.type else {
                report(
                    "cannot use optional chaining on non-optional value of type '\(base.type)'", at: chain.questionMark)
                return nil
            }
            chains[chain.id] = Typed(.chained, wrapped)
            defer { chains[chain.id] = nil }
            guard let rest = expression(expr, expecting: expected?.unwrapped) else { return nil }
            return Typed(.chain(base, rest), rest.type.isOptional ? rest.type : .optional(rest.type))
        }
        if let chain = expr.as(OptionalChainingExprSyntax.self) {
            if let value = chains[chain.id] { return value }
            report("'?' must be followed by a call, member lookup, or subscript", at: chain.questionMark)
            return nil
        }
        if let literal = expr.as(IntegerLiteralExprSyntax.self) {
            return integer(literal, negative: false, expecting: expected)
        }
        if let literal = expr.as(FloatLiteralExprSyntax.self) {
            return Typed(.double(Double(literal.literal.text.filter { $0 != "_" }) ?? 0), .double)
        }
        if let literal = expr.as(BooleanLiteralExprSyntax.self) {
            return Typed(.bool(literal.literal.tokenKind == .keyword(.true)), .bool)
        }
        if let literal = expr.as(StringLiteralExprSyntax.self) { return string(literal, expecting: expected) }
        if let keyPath = expr.as(KeyPathExprSyntax.self) { return self.keyPath(keyPath, expecting: expected) }
        if expr.is(NilLiteralExprSyntax.self) {
            if let expected, let made = nilLiteral(as: expected, at: expr) { return made }
            guard let expected, expected.isOptional || expected == .dynamic || expected == .any else {
                report(
                    expected == nil
                        ? "'nil' requires a contextual type"
                        : "'nil' is not compatible with expected type '\(expected!)'", at: expr)
                return nil
            }
            return Typed(.nil, expected.isOptional ? expected : .optional(expected))
        }
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            if case .binaryOperator(let op) = reference.baseName.tokenKind {
                return operatorFunction(op, expecting: expected, at: reference)
            }
            return self.reference(reference.baseName.text, at: reference, expecting: expected)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            let outer = effectSite
            effectSite = Syntax(member)
            defer { effectSite = outer }
            return memberAccess(member, expecting: expected)
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            let outer = effectSite
            effectSite = Syntax(call)
            defer { effectSite = outer }
            return self.call(call, expecting: expected)
        }
        if let subscriptCall = expr.as(SubscriptCallExprSyntax.self) { return subscripted(subscriptCall) }
        if let infix = expr.as(InfixOperatorExprSyntax.self) { return self.infix(infix, expecting: expected) }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self) { return self.prefix(prefix, expecting: expected) }
        if let ternary = expr.as(TernaryExprSyntax.self) { return self.ternary(ternary, expecting: expected) }
        if let tryExpr = expr.as(TryExprSyntax.self) { return tried(tryExpr, expecting: expected) }
        if let awaitExpr = expr.as(AwaitExprSyntax.self) {
            let outer = marks.awaited
            marks.awaited = true
            defer { marks.awaited = outer }
            guard let inner = expression(awaitExpr.expression, expecting: expected) else { return nil }
            return Typed(.await(inner), inner.type)
        }
        if let array = expr.as(ArrayExprSyntax.self) { return self.array(array, expecting: expected) }
        if let dictionary = expr.as(DictionaryExprSyntax.self) {
            return self.dictionary(dictionary, expecting: expected)
        }
        if let closure = expr.as(ClosureExprSyntax.self) { return self.closure(closure, expecting: expected) }
        if let tuple = expr.as(TupleExprSyntax.self) { return self.tuple(tuple, expecting: expected) }
        if let force = expr.as(ForceUnwrapExprSyntax.self) {
            guard let value = expression(force.expression, expecting: expected.map(SwiftType.optional)) else {
                return nil
            }
            guard case .optional(let wrapped) = value.type else {
                if value.type == .dynamic || value.type == .unresolved { return Typed(.force(value), value.type) }
                report("cannot force unwrap value of non-optional type '\(value.type)'", at: force.exclamationMark)
                return nil
            }
            return Typed(.force(value), wrapped)
        }
        if let asExpr = expr.as(AsExprSyntax.self) { return cast(asExpr) }
        if let isExpr = expr.as(IsExprSyntax.self) {
            guard let value = expression(isExpr.expression, expecting: nil) else { return nil }
            let type = resolveWritten(isExpr.type)
            return Typed(.cast(value, type, .check), .bool)
        }
        if expr.is(DiscardAssignmentExprSyntax.self) {
            report("'_' can only appear in a pattern or on the left side of an assignment", at: expr)
            return nil
        }
        if let ifExpr = expr.as(IfExprSyntax.self) {
            report("'if' as a value isn't supported; assign in each branch", at: ifExpr.ifKeyword)
            return nil
        }
        if let switchExpr = expr.as(SwitchExprSyntax.self) {
            report("'switch' as a value isn't supported; assign in each case", at: switchExpr.switchKeyword)
            return nil
        }
        report("this expression isn't supported", at: expr)
        return nil
    }

    /// The optional chain an expression's base is in: `a?` in `a?.b.c()`.
    static func chain(in expr: ExprSyntax) -> OptionalChainingExprSyntax? {
        var current = expr
        while true {
            if let chain = current.as(OptionalChainingExprSyntax.self) { return chain }
            if let member = current.as(MemberAccessExprSyntax.self), let base = member.base {
                current = base
            } else if let call = current.as(FunctionCallExprSyntax.self) {
                current = call.calledExpression
            } else if let subscriptCall = current.as(SubscriptCallExprSyntax.self) {
                current = subscriptCall.calledExpression
            } else if let force = current.as(ForceUnwrapExprSyntax.self) {
                current = force.expression
            } else {
                return nil
            }
        }
    }

    // MARK: Literals

    /// A string literal: a `Character` or a `Unicode.Scalar` where one is expected and it's one, as Swift
    /// reads a literal by the type it's given.
    private func string(_ literal: StringLiteralExprSyntax, expecting expected: SwiftType?) -> Typed? {
        var pieces: [Piece] = []
        for segment in literal.segments {
            switch segment {
            case .stringSegment(let text):
                // Text next to text is one piece, however the literal's segments split it.
                if case .text(let before)? = pieces.last {
                    pieces[pieces.count - 1] = .text(before + Self.unescaped(text.content.text))
                } else {
                    pieces.append(.text(Self.unescaped(text.content.text)))
                }
            case .expressionSegment(let interpolation):
                guard interpolation.expressions.count == 1, let only = interpolation.expressions.first,
                    only.label == nil
                else {
                    report("this interpolation isn't supported", at: interpolation)
                    return nil
                }
                guard let value = expression(only.expression, expecting: nil) else { return nil }
                pieces.append(.value(value))
            }
        }
        if pieces.count <= 1, case .text(let text)? = pieces.first ?? .text("") {
            if expected?.unwrapped == .character, text.count == 1, let character = text.first {
                return Typed(.character(character), .character)
            }
            if expected?.unwrapped == .named("Unicode.Scalar"), text.unicodeScalars.count == 1,
                let scalar = text.unicodeScalars.first
            {
                return Typed(.scalar(scalar), .named("Unicode.Scalar"))
            }
            // A literal is a `Substring` where one is expected, as any type that takes text.
            if expected?.unwrapped == .named("Substring") { return Typed(.string(text), .named("Substring")) }
            return Typed(.string(text), .string)
        }
        return Typed(.interpolation(pieces), .string)
    }

    static func unescaped(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "r": result.append("\r")
                case "0": result.append("\0")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    private func array(_ array: ArrayExprSyntax, expecting expected: SwiftType?) -> Typed? {
        // A `Set` written as an array literal, where one is expected.
        if case .named("Set", let arguments)? = expected?.unwrapped, let element = arguments.first, !element.isOpen {
            guard let elements = self.array(array, expecting: .array(element)) else { return nil }
            return Typed(
                .standard(StandardMember(type: "Set", member: "init(_:)"), on: nil, [.value(elements)]),
                .named("Set", arguments: [element]))
        }
        var element: SwiftType?
        if case .array(let declared)? = expected?.unwrapped { element = declared }
        if expected == .any || expected?.unwrapped == .existential([]) { element = .any }
        var elements: [Typed] = []
        for item in array.elements {
            guard let value = expression(item.expression, expecting: element) else { return nil }
            if let type = element {
                guard let converted = convert(value, to: type, at: item.expression, as: .element) else { return nil }
                elements.append(converted)
            } else {
                element = value.type
                elements.append(value)
            }
        }
        guard let element else {
            report("empty collection literal requires an explicit type", at: array)
            return nil
        }
        return Typed(.array(elements), .array(element))
    }

    private func dictionary(_ dictionary: DictionaryExprSyntax, expecting expected: SwiftType?) -> Typed? {
        var key: SwiftType?
        var value: SwiftType?
        if case .dictionary(let declaredKey, let declaredValue)? = expected?.unwrapped {
            (key, value) = (declaredKey, declaredValue)
        }
        guard case .elements(let list) = dictionary.content else {
            guard let key, let value else {
                report("empty collection literal requires an explicit type", at: dictionary)
                return nil
            }
            return Typed(.dictionary([]), .dictionary(key: key, value: value))
        }
        var pairs: [(Typed, Typed)] = []
        for element in list {
            guard let keyValue = expression(element.key, expecting: key),
                let valueValue = expression(element.value, expecting: value)
            else {
                return nil
            }
            let keyType = key ?? keyValue.type
            let valueType = value ?? valueValue.type
            (key, value) = (keyType, valueType)
            guard let convertedKey = convert(keyValue, to: keyType, at: element.key, as: .element),
                let convertedValue = convert(valueValue, to: valueType, at: element.value, as: .element)
            else { return nil }
            pairs.append((convertedKey, convertedValue))
        }
        return Typed(.dictionary(pairs), .dictionary(key: key!, value: value!))
    }

    private func tuple(_ tuple: TupleExprSyntax, expecting expected: SwiftType?) -> Typed? {
        if tuple.elements.count == 1, let only = tuple.elements.first, only.label == nil {
            return expression(only.expression, expecting: expected)
        }
        if tuple.elements.isEmpty { return Typed(.tuple([]), .void) }
        var expectedElements: [SwiftType]?
        if case .tuple(let elements, _)? = expected, elements.count == tuple.elements.count {
            expectedElements = elements
        }
        var values: [Typed] = []
        for (index, element) in tuple.elements.enumerated() {
            guard let value = expression(element.expression, expecting: expectedElements?[index]) else { return nil }
            values.append(expectedElements.flatMap { converted(value, to: $0[index]) } ?? value)
        }
        return Typed(.tuple(values), .tuple(values.map(\.type), labels: tuple.elements.map { $0.label?.text }))
    }

    // MARK: Names

    /// A name, as Swift finds it: a local, `self`, a member of `self`, a global, or a type.
    func reference(_ name: String, at node: some SyntaxProtocol, expecting expected: SwiftType? = nil) -> Typed? {
        if let (binding, depth) = context.lookup(name) {
            if context.unassigned.contains(Local(depth: binding.frameDepth, slot: binding.slot)) {
                report("\(binding.mutable ? "variable" : "constant") '\(name)' used before being initialized", at: node)
                return nil
            }
            return Typed(.local(Local(depth: depth, slot: binding.slot)), binding.type)
        }
        if name == "self" {
            guard let selfType = context.selfType else {
                report("cannot find 'self' in scope; did you mean to use it in a type or extension context?", at: node)
                return nil
            }
            return Typed(
                .selfValue,
                context.isStatic ? .named(selfType.name) : context.selfValueTypeInScope ?? selfType.declaredType)
        }
        // A member of `self`, written without it.
        if let selfType = context.selfType, let member = implicitSelfMember(name, of: selfType, at: node) {
            return member
        }
        // A method of `self`, or a function, as a value: `numbers.map(describe)`.
        if let selfType = context.selfType, let methods = selfType.methods[name] {
            let base = Typed(
                .selfValue,
                context.isStatic ? .named(selfType.name) : context.selfValueTypeInScope ?? selfType.declaredType)
            return functionValue(
                methods.filter { $0.isStatic == context.isStatic }, on: base, expecting: expected, named: name, at: node
            )
        }
        if module.globals[name] != nil, let type = globalType(name) { return Typed(.global(name), type) }
        if module.lookup(name, in: context.selfType?.name) != nil && module.names(name, in: checkedName)
            || ["Int", "Double", "String", "Bool"].contains(name)
        {
            report("expected member name or constructor call after type name", at: node)
            return nil
        }
        if let functions = module.functions[name] {
            return functionValue(functions, on: nil, expecting: expected, named: name, at: node)
        }
        report("cannot find '\(name)' in scope", at: node)
        return nil
    }

    /// A function as a value: a closure calling it with what it's given, chosen of its overloads
    /// by the function type expected, or the only one.
    private func functionValue(
        _ candidates: [Function], on base: Typed?, expecting expected: SwiftType?, named name: String,
        at node: some SyntaxProtocol
    ) -> Typed? {
        let fitting = candidates.filter { candidate in
            guard case .function(let parameters, _, _)? = expected?.unwrapped else { return true }
            return candidate.parameters.count == parameters.count && candidate.generics.isEmpty
        }
        guard
            let function = fitting.count == 1
                ? fitting.first
                : fitting.first(where: { candidate in
                    guard let expected else { return false }
                    return converted(Typed(.chained, candidate.type), to: expected.unwrapped) != nil
                })
        else {
            report(
                fitting.isEmpty
                    ? "cannot convert '\(name)' to the function type expected" : "ambiguous use of '\(name)'", at: node)
            return nil
        }
        if function.generics.isEmpty == false || function.parameters.contains(where: { $0.isInout || $0.isVariadic }) {
            report("'\(name)' as a value isn't supported; call it in a closure", at: node)
            return nil
        }
        let closure = Closure(parameters: function.parameters.count)
        closure.slots = function.parameters.count
        let arguments = function.parameters.enumerated().map { index, parameter in
            Argument.value(Typed(.local(Local(depth: 0, slot: index)), parameter.type))
        }
        let call: Expression =
            isStandard(function)
            ? .standard(StandardMember(type: "", member: function.written), on: nil, arguments)
            : .call(resolvedBody(of: function), on: base.map { Typed($0.expression, $0.type) }, arguments)
        // The base is read where the closure runs, from the frame it was made in.
        closure.body = [.return(Typed(call, function.result))]
        return Typed(.closure(closure), function.type)
    }

    /// An operator as a function, where one taking two values is expected: `+` in `reduce(0, +)`.
    private func operatorFunction(_ op: String, expecting expected: SwiftType?, at node: some SyntaxProtocol) -> Typed?
    {
        guard case .function(let parameters, let result, _)? = expected?.unwrapped, parameters.count == 2,
            let left = parameters.first, let right = parameters.last, !left.isOpen, !right.isOpen
        else {
            report("an operator as a value needs the function type it's used as", at: node)
            return nil
        }
        let valid: Bool
        switch (op, left) {
        case ("+", .int), ("-", .int), ("*", .int), ("+", .double), ("-", .double), ("*", .double), ("/", .double),
            ("+", .string):
            valid = left == right && (result == left || result.isOpen)
        case ("<", _), (">", _), ("<=", _), (">=", _):
            valid = left == right && conforms(left, to: "Comparable")
        case ("==", _), ("!=", _):
            valid = left == right && conforms(left, to: "Equatable")
        default:
            valid = false
        }
        guard valid else {
            report("cannot convert value of type operator '\(op)' to expected argument type '\(expected!)'", at: node)
            return nil
        }
        let returns: SwiftType = ["<", ">", "<=", ">=", "==", "!="].contains(op) ? .bool : left
        let closure = Closure(parameters: 2)
        closure.slots = 2
        closure.body = [
            .return(
                Typed(
                    .binary(
                        op, Typed(.local(Local(depth: 0, slot: 0)), left),
                        Typed(.local(Local(depth: 0, slot: 1)), right)), returns))
        ]
        return Typed(.closure(closure), .function(parameters: [left, right], result: returns, effects: .none))
    }

    private func implicitSelfMember(_ name: String, of type: TypeDeclaration, at node: some SyntaxProtocol) -> Typed? {
        let selfValue = context.selfValueTypeInScope ?? type.declaredType
        guard
            let (property, declaring) = type.properties[name].map({ ($0, type) })
                ?? (context.isStatic ? nil : instanceProperty(name, of: selfValue))
        else { return nil }
        if property.isStatic != context.isStatic {
            report("instance member '\(name)' cannot be used on type '\(type.name)'", at: node)
            return nil
        }
        let base = Typed(.selfValue, context.isStatic ? .named(type.name) : selfValue)
        return propertyValue(property, of: declaring, on: base, at: node)
    }

    /// A property's value, on a value of its type.
    func propertyValue(_ property: Property, of type: TypeDeclaration, on base: Typed, at node: some SyntaxProtocol)
        -> Typed?
    {
        let propertyType = propertyType(property, of: type).substituting(typeBindings(of: base.type))
        // A library type written in Swift, each initializer with its body, keeps what it stores as
        // any struct does.
        let storedAsWritten =
            property.isStored && !type.initializers.isEmpty && type.initializers.allSatisfy(Self.hasBody)
        // The standard library's own, which the interpreter reads; or one written in Swift, for
        // the value it's read of.
        if let getter = property.getter, !storedAsWritten, isStandard(getter) || type.kind == .protocol {
            if property.effects.throwing { markThrows(at: node, property: true) }
            if property.effects.async { markAwait(at: node) }
            if isNative(getter) {
                return Typed(
                    .standard(StandardMember(type: type.name, member: property.name), on: base, []), propertyType)
            }
            return Typed(.computed(base, resolvedBody(of: getter, for: base.type)), propertyType)
        }
        if property.isStored, let index = type.stored.firstIndex(where: { $0.name == property.name }) {
            if context.kind == .initializer, context.unassignedStored.contains(property.name),
                case .selfValue = base.expression
            {
                report("'self' used before all stored properties are initialized", at: node)
                return nil
            }
            return Typed(.stored(base, index: index), propertyType)
        }
        guard let getter = property.getter else { return Typed(.stored(base, index: 0), propertyType) }
        if property.effects.throwing { markThrows(at: node, property: true) }
        if property.effects.async { markAwait(at: node) }
        return Typed(.computed(base, resolvedBody(of: getter)), propertyType)
    }

    // MARK: Members

    private func memberAccess(_ member: MemberAccessExprSyntax, expecting expected: SwiftType?) -> Typed? {
        let name = member.declName.baseName.text
        guard let baseSyntax = member.base else {
            return implicitMember(name, arguments: nil, expecting: expected, at: member)
        }
        if name == "init", let typeName = typeName(of: baseSyntax) {
            return initializerValue(typeName, expecting: expected, at: member)
        }
        if name == "self", let type = writtenType(baseSyntax) {
            return Typed(.metatype(type), .metatype(type))
        }
        if let typeName = typeName(of: baseSyntax) {
            return staticMember(name, of: typeName, arguments: nil, expecting: expected, at: member)
        }
        guard let base = expression(baseSyntax, expecting: nil) else { return nil }
        return self.member(name, of: base, at: member.declName)
    }

    /// The type an expression is written as, when it's one, read as a type is: `Int`, `T`, `[Int]`,
    /// `Box<Int>` before `.self`. A value, such as a local, is a value.
    func writtenType(_ expr: ExprSyntax) -> SwiftType? {
        func namesType(_ expr: ExprSyntax) -> Bool {
            if typeName(of: expr) != nil { return true }
            if let reference = expr.as(DeclReferenceExprSyntax.self) {
                let name = reference.baseName.text
                return context.lookup(name) == nil && context.typeBindingsInScope[name] != nil
            }
            if let specialized = expr.as(GenericSpecializationExprSyntax.self) {
                return namesType(specialized.expression)
            }
            if let array = expr.as(ArrayExprSyntax.self), array.elements.count == 1 {
                return namesType(array.elements.first!.expression)
            }
            if let dictionary = expr.as(DictionaryExprSyntax.self),
                case .elements(let elements) = dictionary.content, elements.count == 1
            {
                return namesType(elements.first!.key) && namesType(elements.first!.value)
            }
            if let optional = expr.as(OptionalChainingExprSyntax.self) { return namesType(optional.expression) }
            return false
        }
        guard namesType(expr) else { return nil }
        let parsed = Parser.parse(source: "let _: \(expr.trimmedDescription)")
        guard let variable = parsed.statements.first?.item.as(VariableDeclSyntax.self),
            let type = variable.bindings.first?.typeAnnotation?.type
        else { return nil }
        let resolved = resolveWritten(type)
        return resolved == .unresolved ? nil : resolved
    }

    /// The type an expression names, when it names one: `Item` in `Item.text`.
    func typeName(of expr: ExprSyntax) -> String? {
        // A nested type, named with what it's in: `Unicode.Scalar`.
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base, let outer = typeName(of: base),
            module.type(named: "\(outer).\(member.declName.baseName.text)") != nil
        {
            return "\(outer).\(member.declName.baseName.text)"
        }
        guard let reference = expr.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = reference.baseName.text
        guard context.lookup(name) == nil, !(context.selfType?.properties[name] != nil), module.globals[name] == nil
        else { return nil }
        if let bound = context.typeBindingsInScope[name], let declared = bound.declarationName,
            module.type(named: declared) != nil
        {
            return declared
        }
        guard module.names(name, in: checkedName) else { return nil }
        // Looked up from the type it's written in outward: `Reason` in `Desk` is `Desk.Reason`.
        if let found = module.lookup(name, in: context.selfType?.name) { return found }
        if let alias = module.aliases[name], case .named(let target, _) = module.resolve(alias, generics: [], file: "")
        {
            return target
        }
        return nil
    }

    /// A member of a value: a property, an element of a tuple, or another object's published value.
    func member(_ name: String, of base: Typed, at node: some SyntaxProtocol) -> Typed? {
        switch base.type {
        case .unresolved:
            return Typed(.read(base, name), .unresolved)
        case .optional(let wrapped):
            report(
                "value of optional type '\(base.type)' must be unwrapped to refer to member '\(name)' of wrapped base type '\(wrapped)'",
                at: node)
            return nil
        case .tuple(let elements, let labels):
            if let index = Int(name), index < elements.count { return Typed(.element(base, index), elements[index]) }
            if let index = labels.firstIndex(of: name) { return Typed(.element(base, index), elements[index]) }
            report("value of tuple type '\(base.type)' has no member '\(name)'", at: node)
            return nil
        case .dynamic, .existential(["Actor"]):
            // Another object of a type that isn't declared: what it publishes, read.
            markAwait(at: node)
            markThrows(at: node, property: true)
            return Typed(.read(base, name), .dynamic)
        default:
            break
        }
        if case .named(let typeName, _) = base.type, let type = module.type(named: typeName) {
            if name == "rawValue", type.kind == .enumeration, let raw = type.rawType {
                return Typed(.rawValue(base), raw)
            }
            guard let (property, declaring) = instanceProperty(name, of: base.type), !property.isStatic else {
                report("value of type '\(base.type)' has no member '\(name)'", at: node)
                return nil
            }
            if declaring !== type { return propertyValue(property, of: declaring, on: base, at: node) }
            if isOtherActor(base, type) {
                // Another object's state: read by asking it.
                markAwait(at: node)
                if property.effects.throwing { markThrows(at: node, property: true) }
                return Typed(.read(base, name), propertyType(property, of: type))
            }
            return propertyValue(property, of: type, on: base, at: node)
        }
        guard let (property, declaring) = instanceProperty(name, of: base.type), !property.isStatic else {
            report("value of type '\(base.type)' has no member '\(name)'", at: node)
            return nil
        }
        return propertyValue(property, of: declaring, on: base, at: node)
    }

    /// Whether a value is an actor other than the one running: its state is asked for.
    func isOtherActor(_ value: Typed, _ type: TypeDeclaration) -> Bool {
        guard type.kind == .actor else { return false }
        if case .selfValue = value.expression { return false }
        return true
    }

    /// `nil` as a value of `type` when it's a type of the module's that takes it, conforming to
    /// `ExpressibleByNilLiteral`: what its `init(nilLiteral:)` makes. An optional's `nil` is its own.
    func nilLiteral(as type: SwiftType, at node: some SyntaxProtocol) -> Typed? {
        guard !type.isOptional, let name = type.declarationName, name != "Optional",
            conforms(type, to: "ExpressibleByNilLiteral"),
            let call = Parser.parse(source: "_ = T(nilLiteral: ())").statements.first?.item.as(SequenceExprSyntax.self)?
                .elements.last?
                .as(FunctionCallExprSyntax.self)
        else { return nil }
        return initializer(name, arguments: CallArguments(call.arguments, trailing: nil), expecting: type, at: node)
    }

    /// `.member` where the type is what's expected: an enum's case, or a static member.
    func implicitMember(
        _ name: String, arguments: CallArguments?, expecting expected: SwiftType?, at node: some SyntaxProtocol
    ) -> Typed? {
        guard let expected, let typeName = expected.unwrapped.declarationName else {
            report("cannot infer contextual base in reference to member '\(name)'", at: node)
            return nil
        }
        if case .optional(let wrapped) = expected, name == "none" || name == "some" {
            return optional(name, arguments: arguments, wrapping: wrapped, at: node)
        }
        return staticMember(name, of: typeName, arguments: arguments, expecting: expected.unwrapped, at: node)
    }

    /// `Optional`'s case `name`, `.none` or `.some(value)`, as the optional value it is: holding a
    /// `wrapped`, or as its value is when that isn't known.
    func optional(_ name: String, arguments: CallArguments?, wrapping wrapped: SwiftType?, at node: some SyntaxProtocol)
        -> Typed?
    {
        if name == "none" {
            guard let wrapped else {
                report("generic parameter 'Wrapped' could not be inferred", at: node)
                return nil
            }
            return Typed(.nil, .optional(wrapped))
        }
        guard let arguments else {
            report("enum case 'some' has associated values; use 'Optional.some(…)'", at: node)
            return nil
        }
        guard let only = arguments.values.first, arguments.values.count == 1, only.label == nil else {
            report("enum case 'some' takes one value, without a label", at: node)
            return nil
        }
        guard let value = expression(only.expression, expecting: wrapped) else { return nil }
        guard let wrapped else { return Typed(.wrap(value), .optional(value.type)) }
        guard let converted = convert(value, to: wrapped, at: only.expression, as: .argument) else { return nil }
        return Typed(.wrap(converted), .optional(wrapped))
    }

    /// A type's static member: an enum's case, a static property, or a static method, called with
    /// `arguments` when it's called.
    func staticMember(
        _ name: String, of typeName: String, arguments: CallArguments?, expecting expected: SwiftType?,
        at node: some SyntaxProtocol
    ) -> Typed? {
        guard let type = module.type(named: typeName) else {
            report("cannot find type '\(typeName)' in scope", at: node)
            return nil
        }
        if typeName == "Optional", name == "none" || name == "some" {
            guard case .optional(let wrapped)? = expected else {
                return optional(name, arguments: arguments, wrapping: nil, at: node)
            }
            return optional(name, arguments: arguments, wrapping: wrapped, at: node)
        }
        if let enumCase = type.case(name) {
            // A generic enum's case is of the enum with its type's arguments: those expected, or
            // those its values are of, as a generic function's are inferred.
            // Inside the enum, its own parameters are the types they stand for there.
            let expectedBindings = expected?.declarationName == typeName ? typeBindings(of: expected!) : [:]
            guard let arguments else {
                if !enumCase.values.isEmpty {
                    report("enum case '\(name)' has associated values; use '\(typeName).\(name)(…)'", at: node)
                    return nil
                }
                let declared = type.declaredType.substituting(expectedBindings)
                if type.generics.contains(where: { expectedBindings[$0] == nil }) {
                    report(
                        "generic parameter '\(type.generics.first { expectedBindings[$0] == nil }!)' could not be inferred",
                        at: node)
                    return nil
                }
                return Typed(.enumCase(typeName, name, []), declared)
            }
            let function = Function(
                name: name, parameters: enumCase.values, result: type.declaredType, effects: .none,
                generics: type.generics, owner: typeName,
                syntax: nil)
            guard
                let (_, resolvedArguments, result) = applied(
                    [function], bindings: expectedBindings, arguments: arguments, expecting: expected, named: name,
                    at: node)
            else { return nil }
            return Typed(.enumCase(typeName, name, resolvedArguments.compactMap(\.typed)), result)
        }
        if let (property, declaring) = staticProperty(name, of: type), arguments == nil {
            let base = Typed(.global(typeName), .named(typeName))
            // Run natively, unless its Swift is written out.
            if type.kind == .standard, !(property.getter.map(Self.hasBody) ?? false) {
                let propertyType = propertyType(property, of: declaring).substituting(
                    typeBindings(of: type.declaredType))
                return Typed(.standard(StandardMember(type: typeName, member: name), on: nil, []), propertyType)
            }
            return propertyValue(property, of: type, on: base, at: node)
        }
        let statics = staticMethods(name, of: type)
        guard !statics.isEmpty else {
            report("type '\(typeName)' has no member '\(name)'", at: node)
            return nil
        }
        guard let arguments else {
            report("static method '\(name)' used as a value isn't supported; call it", at: node)
            return nil
        }
        guard
            let (function, resolvedArguments, result) = applied(
                statics, bindings: typeBindings(of: type.declaredType).filter { !$0.value.isOpen },
                arguments: arguments, expecting: expected, named: name,
                at: node)
        else { return nil }
        markEffects(of: function, arguments: resolvedArguments, at: node)
        if type.kind == .standard, !Self.hasBody(function) {
            return Typed(
                .standard(StandardMember(type: typeName, member: function.written), on: nil, resolvedArguments), result)
        }
        return Typed(.call(resolvedBody(of: function), on: nil, resolvedArguments), result)
    }

    // MARK: Key paths and initializers as functions

    /// A key path where a function is expected: a function of its root reading each of its
    /// properties, as Swift has it. `\.seconds` for `(Track) -> Int`.
    private func keyPath(_ keyPath: KeyPathExprSyntax, expecting expected: SwiftType?) -> Typed? {
        let root: SwiftType
        if let written = keyPath.root {
            root = resolveWritten(written)
        } else if case .function(let parameters, _, _)? = expected?.unwrapped, parameters.count == 1,
            !parameters[0].isOpen
        {
            root = parameters[0]
        } else {
            report("a key path needs the function type it's used as; write a closure", at: keyPath)
            return nil
        }
        var value = Typed(.local(Local(depth: 0, slot: 0)), root)
        for component in keyPath.components {
            guard case .property(let property) = component.component else {
                report("this key path isn't supported; write a closure", at: component)
                return nil
            }
            guard let next = member(property.declName.baseName.text, of: value, at: property.declName) else {
                return nil
            }
            value = next
        }
        let closure = Closure(parameters: 1)
        closure.slots = 1
        closure.body = [.return(value)]
        return Typed(.closure(closure), .function(parameters: [root], result: value.type, effects: .none))
    }

    /// A type's initializer where a function is expected: the one taking what the function is
    /// given. `String.init` for `(Character) -> String`.
    private func initializerValue(_ typeName: String, expecting expected: SwiftType?, at node: some SyntaxProtocol)
        -> Typed?
    {
        guard let type = module.type(named: typeName), case .function(let parameters, _, _)? = expected?.unwrapped,
            !parameters.contains(where: \.isOpen)
        else {
            report("an initializer as a value needs the function type it's used as; write a closure", at: node)
            return nil
        }
        let declared = type.declaredType
        for candidate in initializers(of: type)
        where candidate.parameters.count == parameters.count && !candidate.parameters.contains(where: \.isInout) {
            var bindings = typeBindings(of: declared).filter { !$0.value.isOpen }
            for (parameter, given) in zip(candidate.parameters, parameters) {
                parameter.type.bind(to: given, into: &bindings)
            }
            bindings = withAssociated(bindings)
            let fits = zip(candidate.parameters, parameters).allSatisfy { parameter, given in
                converted(Typed(.chained, given), to: parameter.type.substituting(bindings)) != nil
            }
            guard fits, satisfies(candidate, with: bindings) else { continue }
            let result = candidate.result.substituting(bindings)
            guard !result.isOpen else { continue }
            let arguments = parameters.enumerated().map { index, given in
                Argument.value(Typed(.local(Local(depth: 0, slot: index)), given))
            }
            let made: Expression =
                type.kind == .standard && !Self.hasBody(candidate)
                ? .standard(StandardMember(type: typeName, member: candidate.written), on: nil, arguments)
                : .initialize(typeName, candidate.syntax == nil ? nil : resolvedBody(of: candidate), arguments)
            let closure = Closure(parameters: parameters.count)
            closure.slots = parameters.count
            closure.body = [.return(Typed(made, result))]
            return Typed(.closure(closure), .function(parameters: parameters, result: result, effects: .none))
        }
        report("no '\(typeName).init' takes '\(parameters.map(\.description).joined(separator: ", "))'", at: node)
        return nil
    }

    // MARK: Subscripts

    private func subscripted(_ subscriptCall: SubscriptCallExprSyntax) -> Typed? {
        guard let base = expression(subscriptCall.calledExpression, expecting: nil) else { return nil }
        // Of what couldn't be decided, nothing more is said.
        if base.type == .unresolved {
            unresolvedArguments(CallArguments(subscriptCall.arguments, trailing: nil))
            return Typed(.read(base, "subscript"), .unresolved)
        }
        if base.type == .dynamic {
            report("subscripting another object's answer isn't supported", at: subscriptCall)
            return nil
        }
        guard let declarationName = base.type.declarationName, module.type(named: declarationName) != nil,
            case let candidates = instanceMethods("subscript", of: base.type), !candidates.isEmpty
        else {
            report("value of type '\(base.type)' has no subscripts", at: subscriptCall)
            return nil
        }
        let arguments = CallArguments(subscriptCall.arguments, trailing: nil)
        guard
            let (function, resolvedArguments, result) = applied(
                candidates, bindings: typeBindings(of: base.type), arguments: arguments, expecting: nil,
                named: "subscript", at: subscriptCall)
        else { return nil }
        if let unavailable = Self.unavailable(function) {
            report(unavailable, at: subscriptCall)
            return nil
        }
        return Typed(
            .standard(StandardMember(type: declarationName, member: function.written), on: base, resolvedArguments),
            result)
    }

    // MARK: Operators

    private static let arithmetic: Set<String> = ["+", "-", "*", "/", "%"]
    private static let comparisons: Set<String> = ["<", ">", "<=", ">="]
    private static let equalities: Set<String> = ["==", "!="]
    /// Integers' own operators: bits, and arithmetic that wraps instead of trapping.
    private static let integerOnly: Set<String> = ["&", "|", "^", "&+", "&-", "&*"]
    private static let shifts: Set<String> = ["<<", ">>"]

    private func infix(_ infix: InfixOperatorExprSyntax, expecting expected: SwiftType?) -> Typed? {
        if Self.isAssignment(ExprSyntax(infix)) {
            guard let statement = assignment(infix) else { return nil }
            guard case .assign(let place, let value) = statement else { return Typed(.tuple([]), .void) }
            return Typed(.assignment(place, value), .void)
        }
        guard let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text else {
            report("this operator isn't supported", at: infix.operator)
            return nil
        }
        let (left, right) = (infix.leftOperand, infix.rightOperand)
        switch op {
        case "&&", "||":
            guard let lhs = booleanCondition(left), let rhs = booleanCondition(right) else { return nil }
            return Typed(op == "&&" ? .and(lhs, rhs) : .or(lhs, rhs), .bool)
        case "??":
            guard let lhs = expression(left, expecting: expected.map(SwiftType.optional)) else { return nil }
            guard case .optional(let wrapped) = lhs.type else {
                if lhs.type == .dynamic || lhs.type == .unresolved { return lhs }
                report(
                    "left side of nil coalescing operator '??' has non-optional type '\(lhs.type)', so the right side is never used",
                    at: infix.operator)
                return lhs
            }
            guard let rhs = expression(right, expecting: wrapped) else { return nil }
            if case .optional = rhs.type, let converted = converted(rhs, to: lhs.type) {
                return Typed(.coalesce(lhs, converted), lhs.type)
            }
            guard let converted = convert(rhs, to: wrapped, at: right, as: .argument) else { return nil }
            return Typed(.coalesce(lhs, converted), wrapped)
        case "..<", "...":
            // A range of what isn't an `Int`, such as a string's indices: a `Range`.
            if !Self.isLiteral(left), let lower = speculate({ expression(left, expecting: nil) }), lower.type != .int,
                lower.type != .unresolved
            {
                guard let lhs = expression(left, expecting: nil), let rhs = expression(right, expecting: lhs.type),
                    let upper = convert(rhs, to: lhs.type, at: right, as: .argument)
                else { return nil }
                guard conforms(lhs.type, to: "Comparable") else {
                    report(
                        "referencing operator function '\(op)' on 'Comparable' requires that '\(lhs.type)' conform to 'Comparable'",
                        at: infix.operator)
                    return nil
                }
                return Typed(
                    .range(lhs, upper, closed: op == "..."),
                    .named(op == "..." ? "ClosedRange" : "Range", arguments: [lhs.type]))
            }
            guard let lhs = expression(left, expecting: .int), let rhs = expression(right, expecting: .int),
                let lower = convert(lhs, to: .int, at: left, as: .argument),
                let upper = convert(rhs, to: .int, at: right, as: .argument)
            else { return nil }
            return Typed(.binary(op, lower, upper), .array(.int))
        default:
            break
        }
        // A shift's amount is any integer: the value shifted keeps its type.
        if Self.shifts.contains(op) {
            guard let lhs = expression(left, expecting: expected), let rhs = expression(right, expecting: nil) else {
                return nil
            }
            guard (lhs.type.isInteger || lhs.type == .unresolved) && (rhs.type.isInteger || rhs.type == .unresolved)
            else {
                report(
                    "binary operator '\(op)' cannot be applied to operands of type '\(lhs.type)' and '\(rhs.type)'",
                    at: infix.operator)
                return nil
            }
            return Typed(.binary(op, lhs, rhs), lhs.type)
        }
        guard
            Self.arithmetic.contains(op) || Self.comparisons.contains(op) || Self.equalities.contains(op)
                || Self.integerOnly.contains(op)
        else {
            report("operator '\(op)' isn't supported", at: infix.operator)
            return nil
        }
        // `x == nil`: any optional, whatever its value's type.
        if Self.equalities.contains(op), left.is(NilLiteralExprSyntax.self) || right.is(NilLiteralExprSyntax.self) {
            let other = left.is(NilLiteralExprSyntax.self) ? right : left
            guard let value = expression(other, expecting: nil) else { return nil }
            // A type that takes `nil` compares with its own `nil` value, as any two of its values.
            if let made = nilLiteral(as: value.type, at: other) {
                guard conforms(value.type, to: "Equatable") else {
                    report(
                        "binary operator '\(op)' cannot be applied to two '\(value.type)' operands", at: infix.operator)
                    return nil
                }
                return Typed(
                    .binary(
                        op, left.is(NilLiteralExprSyntax.self) ? made : value,
                        left.is(NilLiteralExprSyntax.self) ? value : made), .bool)
            }
            guard value.type.isOptional || value.type == .dynamic || value.type == .unresolved else {
                report(
                    "comparing non-optional value of type '\(value.type)' to 'nil' always returns \(op == "!=")",
                    at: infix.operator)
                return Typed(.bool(op == "!="), .bool)
            }
            return Typed(.binary(op, value, Typed(.nil, value.type)), .bool)
        }
        // A literal takes the other side's type: `x + 1` for a `Double` `x`; text, a `Character`'s,
        // `" " == character`, and is a `String` otherwise.
        let leftIsText = left.is(StringLiteralExprSyntax.self) && !right.is(StringLiteralExprSyntax.self)
        let lhs: Typed
        let rhs: Typed
        if (Self.isLiteral(left) && !Self.isLiteral(right)) || leftIsText {
            guard
                let resolvedRight = expression(
                    right, expecting: Self.arithmetic.contains(op) || Self.integerOnly.contains(op) ? expected : nil),
                let resolvedLeft = expression(
                    left,
                    expecting: !leftIsText || resolvedRight.type.unwrapped == .character ? resolvedRight.type : nil)
            else { return nil }
            (lhs, rhs) = (resolvedLeft, resolvedRight)
        } else {
            guard
                let resolvedLeft = expression(
                    left, expecting: Self.arithmetic.contains(op) || Self.integerOnly.contains(op) ? expected : nil),
                // Foundation's `Date + TimeInterval`: what's added to a date is seconds.
                let resolvedRight = expression(
                    right,
                    expecting: resolvedLeft.type == .named("Date") && (op == "+" || op == "-")
                        ? .double : resolvedLeft.type)
            else { return nil }
            (lhs, rhs) = (resolvedLeft, resolvedRight)
        }
        // Text of either kind compares with and adds to text of the other, as `StringProtocol`
        // has it: `String` and `Substring`.
        if lhs.type != rhs.type, conforms(lhs.type, to: "StringProtocol"), conforms(rhs.type, to: "StringProtocol"),
            Self.equalities.contains(op) || Self.comparisons.contains(op) || op == "+"
        {
            return Typed(.binary(op, lhs, rhs), op == "+" ? lhs.type : .bool)
        }
        // Each side as the other's type, where one converts: `Int?` and `Int`.
        var (a, b) = (lhs, rhs)
        if a.type != b.type {
            if let converted = converted(b, to: a.type) {
                b = converted
            } else if let converted = converted(a, to: b.type) {
                a = converted
            }
        }
        if a.type == .named("Date"), b.type == .double, op == "+" || op == "-" {
            return Typed(.binary(op, a, b), a.type)
        }
        let type = a.type
        guard type == b.type else {
            report(
                "binary operator '\(op)' cannot be applied to operands of type '\(lhs.type)' and '\(rhs.type)'",
                at: infix.operator)
            return nil
        }
        if type == .dynamic || type == .unresolved {
            return Typed(
                .binary(op, a, b), Self.equalities.contains(op) || Self.comparisons.contains(op) ? .bool : type)
        }
        if Self.equalities.contains(op) {
            guard conforms(type, to: "Equatable") else {
                report("binary operator '\(op)' cannot be applied to two '\(type)' operands", at: infix.operator)
                return nil
            }
            return Typed(.binary(op, a, b), .bool)
        }
        if Self.comparisons.contains(op), case .tuple(let elements, _) = type, elements.count <= 6 {
            guard elements.allSatisfy({ conforms($0, to: "Comparable") }) else {
                report("binary operator '\(op)' cannot be applied to two '\(type)' operands", at: infix.operator)
                return nil
            }
            return Typed(.binary(op, a, b), .bool)
        }
        if Self.comparisons.contains(op) {
            guard conforms(type, to: "Comparable") || type == .named("Duration") else {
                report("binary operator '\(op)' cannot be applied to two '\(type)' operands", at: infix.operator)
                return nil
            }
            return Typed(.binary(op, a, b), .bool)
        }
        switch (op, type) {
        case (_, .int), (_, .fixedInteger), ("+", .string), ("+", .array), ("-", .double), ("+", .double),
            ("*", .double), ("/", .double), ("+", .named("Duration", [])),
            ("+", .named("Decimal", [])), ("-", .named("Decimal", [])), ("*", .named("Decimal", [])),
            ("/", .named("Decimal", [])):
            return Typed(.binary(op, a, b), type)
        default:
            report("binary operator '\(op)' cannot be applied to two '\(type)' operands", at: infix.operator)
            return nil
        }
    }

    /// An integer literal, of the type expected where it's an integer type or `Double`, else `Int`,
    /// as Swift reads its digits: decimal, `0x`, `0o` or `0b`, with `_` between.
    private func integer(_ literal: IntegerLiteralExprSyntax, negative: Bool, expecting expected: SwiftType?) -> Typed?
    {
        let text = (negative ? "-" : "") + literal.literal.text
        guard let magnitude = Self.magnitude(of: literal.literal.text) else {
            report(
                "integer literal '\(text)' overflows when stored into '\(expected?.unwrapped.isInteger == true ? expected!.unwrapped : .int)'",
                at: literal)
            return nil
        }
        switch expected?.unwrapped {
        case .double?:
            return Typed(.double((negative ? -1 : 1) * Double(magnitude)), .double)
        case .fixedInteger(let kind)?:
            if !kind.isSigned, negative, magnitude != 0 {
                report(
                    "negative integer '\(text)' overflows when stored into unsigned type '\(kind.rawValue)'",
                    at: literal)
                return nil
            }
            let limit: UInt64 =
                kind.isSigned
                ? (UInt64(1) << UInt64(kind.bitWidth - 1)) - (negative ? 0 : 1)
                : UInt64.max >> UInt64(64 - kind.bitWidth)
            guard magnitude <= limit else {
                report("integer literal '\(text)' overflows when stored into '\(kind.rawValue)'", at: literal)
                return nil
            }
            return Typed(.fixedInteger(kind, bits: negative ? 0 &- magnitude : magnitude), .fixedInteger(kind))
        default:
            let limit = UInt64(Int.max) + (negative ? 1 : 0)
            guard magnitude <= limit else {
                report("integer literal '\(text)' overflows when stored into 'Int'", at: literal)
                return nil
            }
            return Typed(.integer(negative ? Int(truncatingIfNeeded: 0 &- magnitude) : Int(magnitude)), .int)
        }
    }

    /// An integer literal's digits as a number: `nil` past 64 bits.
    static func magnitude(of literal: String) -> UInt64? {
        let digits = literal.filter { $0 != "_" }
        for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where digits.hasPrefix(prefix) {
            return UInt64(digits.dropFirst(2), radix: radix)
        }
        return UInt64(digits)
    }

    static func isLiteral(_ expr: ExprSyntax) -> Bool {
        expr.is(IntegerLiteralExprSyntax.self) || expr.is(FloatLiteralExprSyntax.self)
            || (expr.as(PrefixOperatorExprSyntax.self).map { isLiteral($0.expression) } ?? false)
    }

    private func prefix(_ prefix: PrefixOperatorExprSyntax, expecting expected: SwiftType?) -> Typed? {
        switch prefix.operator.text {
        case "!":
            guard let value = booleanCondition(prefix.expression) else { return nil }
            return Typed(.unary("!", value), .bool)
        case "-":
            if let literal = prefix.expression.as(IntegerLiteralExprSyntax.self) {
                return integer(literal, negative: true, expecting: expected)
            }
            guard let value = expression(prefix.expression, expecting: expected) else { return nil }
            let signedInteger = if case .fixedInteger(let kind) = value.type { kind.isSigned } else { false }
            guard value.type == .int || value.type == .double || signedInteger else {
                report(
                    "unary operator '-' cannot be applied to an operand of type '\(value.type)'", at: prefix.operator)
                return nil
            }
            if case .integer(let number) = value.expression { return Typed(.integer(-number), .int) }
            if case .double(let number) = value.expression { return Typed(.double(-number), .double) }
            return Typed(.unary("-", value), value.type)
        case "~":
            guard let value = expression(prefix.expression, expecting: expected) else { return nil }
            guard value.type.isInteger || value.type == .unresolved else {
                report(
                    "unary operator '~' cannot be applied to an operand of type '\(value.type)'", at: prefix.operator)
                return nil
            }
            return Typed(.unary("~", value), value.type)
        default:
            report("operator '\(prefix.operator.text)' isn't supported", at: prefix.operator)
            return nil
        }
    }

    private func ternary(_ ternary: TernaryExprSyntax, expecting expected: SwiftType?) -> Typed? {
        guard let condition = booleanCondition(ternary.condition) else { return nil }
        // A `nil` branch takes the other's type, made optional.
        let thenIsNil = ternary.thenExpression.is(NilLiteralExprSyntax.self)
        let elseIsNil = ternary.elseExpression.is(NilLiteralExprSyntax.self)
        var expectation = expected
        if expectation == nil, thenIsNil, let other = speculate({ expression(ternary.elseExpression, expecting: nil) })
        {
            expectation = .optional(other.type.unwrapped)
        }
        guard let first = expression(ternary.thenExpression, expecting: expectation) else { return nil }
        let type = expectation ?? (elseIsNil ? .optional(first.type.unwrapped) : first.type)
        guard let second = expression(ternary.elseExpression, expecting: type) else { return nil }
        guard let a = convert(first, to: type, at: ternary.thenExpression, as: .argument),
            let b = convert(second, to: type, at: ternary.elseExpression, as: .argument)
        else { return nil }
        return Typed(.ternary(condition, a, b), type)
    }

    // MARK: try, await, casts

    private func tried(_ tryExpr: TryExprSyntax, expecting expected: SwiftType?) -> Typed? {
        let outer = marks.tried
        let kind: Marks.Try
        switch tryExpr.questionOrExclamationMark?.tokenKind {
        case .postfixQuestionMark?: kind = .optional
        case .exclamationMark?: kind = .forced
        default: kind = .plain
        }
        // An outer `try` that handles errors still does, inside.
        marks.tried = outer == .optional || outer == .forced ? outer : kind
        defer { marks.tried = outer }
        guard let inner = expression(tryExpr.expression, expecting: kind == .optional ? expected?.unwrapped : expected)
        else { return nil }
        switch kind {
        case .plain: return Typed(.try(inner), inner.type)
        case .forced: return Typed(.tryForce(inner), inner.type)
        case .optional: return Typed(.tryOptional(inner), inner.type.isOptional ? inner.type : .optional(inner.type))
        }
    }

    private func cast(_ asExpr: AsExprSyntax) -> Typed? {
        let type = resolveWritten(asExpr.type)
        switch asExpr.questionOrExclamationMark?.tokenKind {
        case .postfixQuestionMark?:
            guard let value = expression(asExpr.expression, expecting: nil) else { return nil }
            return Typed(.cast(value, type, .conditional), .optional(type))
        case .exclamationMark?:
            guard let value = expression(asExpr.expression, expecting: nil) else { return nil }
            return Typed(.cast(value, type, .forced), type)
        default:
            guard let value = expression(asExpr.expression, expecting: type) else { return nil }
            return convert(value, to: type, at: asExpr.expression, as: .argument)
        }
    }

    // MARK: Effects

    /// A call that can throw, marked as Swift requires: `try`, in a function that can throw, or
    /// handled by `try?` or `try!`.
    func markThrows(at site: some SyntaxProtocol, thrown: Bool = false, property: Bool = false) {
        let node = thrown ? Syntax(site) : effectSite ?? Syntax(site)
        if !thrown {
            guard let tried = marks.tried else {
                report(
                    property
                        ? "property access can throw, but it is not marked with 'try' and the error is not handled"
                        : "call can throw, but it is not marked with 'try' and the error is not handled", at: node)
                return
            }
            if tried != .plain { return }
        }
        // Caught by a `do` around it.
        if context.catching > 0 { return }
        if context.effectsInferred {
            context.threw = true
        } else if !context.effects.throwing {
            report(
                thrown
                    ? "error is not handled because the enclosing function is not declared 'throws'"
                    : "errors thrown from here are not handled", at: node)
        }
    }

    /// A call that waits, marked as Swift requires: `await`, in a function that can wait.
    func markAwait(at site: some SyntaxProtocol) {
        let node = effectSite ?? Syntax(site)
        // A function that can't wait is told so first, as Swift tells it; then a missing `await`.
        if context.effectsInferred {
            context.awaited = true
        } else if !context.effects.async {
            report("'async' call in a function that does not support concurrency", at: node)
            return
        }
        if !marks.awaited {
            report("expression is 'async' but is not marked with 'await'", at: node)
        }
    }

    /// A call's effects, as its function declares them: `rethrows` throws only what its closures do.
    func markEffects(of function: Function, arguments: [Argument], at node: some SyntaxProtocol) {
        var throwsHere = function.effects.throwing
        if function.isRethrowing {
            throwsHere = arguments.contains { argument in
                guard case .function(_, _, let effects) = argument.typed?.type else { return false }
                return effects.throwing
            }
        }
        if throwsHere { markThrows(at: node) }
        if function.effects.async { markAwait(at: node) }
    }
}

extension Argument {
    var typed: Typed? {
        switch self {
        case .value(let value), .defaulted(let value): value
        case .variadic, .reference: nil
        }
    }
}
