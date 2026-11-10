import SwiftParser
public import SwiftSyntax

/// A call's arguments as written: in parentheses, then its trailing closures.
struct CallArguments: Equatable {
    struct Value: Equatable {
        let label: String?
        let expression: ExprSyntax
        let trailing: Bool
    }

    let values: [Value]

    init(
        _ list: LabeledExprListSyntax, trailing: ClosureExprSyntax?,
        additional: MultipleTrailingClosureElementListSyntax? = nil
    ) {
        var values = list.map { Value(label: $0.label?.text, expression: $0.expression, trailing: false) }
        if let trailing { values.append(Value(label: nil, expression: ExprSyntax(trailing), trailing: true)) }
        for extra in additional ?? [] {
            values.append(Value(label: extra.label.text, expression: ExprSyntax(extra.closure), trailing: true))
        }
        self.values = values
    }
}

extension Resolver {
    func call(_ call: FunctionCallExprSyntax, expecting expected: SwiftType?) -> Typed? {
        let arguments = CallArguments(
            call.arguments, trailing: call.trailingClosure, additional: call.additionalTrailingClosures)
        let callee = call.calledExpression
        // A nested type made: `Unicode.Scalar(value)`.
        if callee.is(MemberAccessExprSyntax.self), let typeName = typeName(of: callee) {
            return initializer(typeName, arguments: arguments, expecting: expected, at: callee)
        }
        if let member = callee.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            guard let baseSyntax = member.base else {
                return implicitMember(name, arguments: arguments, expecting: expected, at: member)
            }
            if let typeName = typeName(of: baseSyntax) {
                if name == "init" {
                    return initializer(typeName, arguments: arguments, expecting: expected, at: member)
                }
                return staticMember(name, of: typeName, arguments: arguments, expecting: expected, at: member.declName)
            }
            return method(name, on: baseSyntax, arguments: arguments, expecting: expected, at: member.declName)
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if context.lookup(name) != nil { return applyValue(callee, arguments: arguments, at: call) }
            if let selfType = context.selfType,
                case let selfValue = context.selfValueTypeInScope ?? selfType.declaredType,
                case let methods = context.isStatic
                    ? (selfType.methods[name] ?? [])
                    : instanceMethods(name, of: selfValue) + (selfType.methods[name] ?? []).filter(\.isStatic),
                !methods.isEmpty
            {
                let candidates = methods.filter { $0.isStatic == context.isStatic }
                guard !candidates.isEmpty else {
                    report("instance member '\(name)' cannot be used on type '\(selfType.name)'", at: reference)
                    return nil
                }
                let base = Typed(.selfValue, context.isStatic ? .named(selfType.name) : selfValue)
                return methodCall(
                    candidates, of: selfType, on: base, place: .selfPlace, arguments: arguments, expecting: expected,
                    named: name, at: reference)
            }
            if context.selfType?.properties[name] != nil { return applyValue(callee, arguments: arguments, at: call) }
            if let typeName = typeName(of: callee) ?? (["Int", "Double", "String", "Bool"].contains(name) ? name : nil)
            {
                // `Self()` in a body resolved for `[Int]` makes an `[Int]`.
                return initializer(
                    typeName, arguments: arguments, expecting: context.typeBindingsInScope[name] ?? expected,
                    at: reference)
            }
            if let functions = module.functions[name] {
                guard
                    let (function, resolvedArguments, result) = applied(
                        functions, bindings: [:], arguments: arguments, expecting: expected, named: name, at: reference)
                else { return nil }
                markEffects(of: function, arguments: resolvedArguments, at: reference)
                if isNative(function) {
                    return Typed(
                        .standard(StandardMember(type: "", member: function.written), on: nil, resolvedArguments),
                        result)
                }
                if isStandard(function) {
                    return Typed(
                        .call(
                            resolvedBody(of: function, for: .void, generics: callBindings[Syntax(reference).id] ?? [:]),
                            on: nil, resolvedArguments), result)
                }
                return Typed(.call(resolvedBody(of: function), on: nil, resolvedArguments), result)
            }
            if module.globals[name] != nil { return applyValue(callee, arguments: arguments, at: call) }
            report("cannot find '\(name)' in scope", at: reference)
            unresolvedArguments(arguments)
            return nil
        }
        // `Set<Character>()`: the type written, with its generic arguments.
        if let specialized = callee.as(GenericSpecializationExprSyntax.self),
            let typeName = typeName(of: specialized.expression)
        {
            return initializer(
                typeName, arguments: arguments, expecting: resolveWritten(Self.type(written: callee)), at: specialized)
        }
        // `[String]()`, `[String: Int]()`: an empty collection of the type written.
        if let array = callee.as(ArrayExprSyntax.self), array.elements.count == 1, arguments.values.isEmpty,
            let element = array.elements.first.map({ Self.type(written: $0.expression) })
        {
            return Typed(.array([]), .array(resolveWritten(element)))
        }
        if let dictionary = callee.as(DictionaryExprSyntax.self), case .elements(let list) = dictionary.content,
            list.count == 1,
            arguments.values.isEmpty, let pair = list.first,
            case (let key, let value) = (Self.type(written: pair.key), Self.type(written: pair.value))
        {
            return Typed(.dictionary([]), .dictionary(key: resolveWritten(key), value: resolveWritten(value)))
        }
        return applyValue(callee, arguments: arguments, at: call)
    }

    /// A type written where an expression is: `String` in `[String]()`.
    static func type(written expression: ExprSyntax) -> TypeSyntax {
        var parser = Parser(expression.trimmedDescription)
        return TypeSyntax.parse(from: &parser)
    }

    /// A call's arguments, when what's called couldn't be decided: resolved still, as Swift
    /// checks them, each closure's parameters of types that couldn't be decided either.
    func unresolvedArguments(_ arguments: CallArguments) {
        for argument in arguments.values { _ = expression(argument.expression, expecting: .unresolved) }
    }

    /// Whether the evaluator runs it itself: the standard library's, or Foundation's.
    func isStandard(_ function: Function) -> Bool {
        let root = function.syntax?.root.id
        return root == StandardLibrary.syntax.root.id || root == FoundationLibrary.syntax.root.id
    }

    /// A closure value, called.
    private func applyValue(_ callee: ExprSyntax, arguments: CallArguments, at node: some SyntaxProtocol) -> Typed? {
        guard let value = expression(callee, expecting: nil) else { return nil }
        if value.type == .unresolved { return value }
        guard case .function(let parameters, let result, let effects) = value.type else {
            report("cannot call value of non-function type '\(value.type)'", at: callee)
            return nil
        }
        guard parameters.count == arguments.values.count else {
            report(
                parameters.count < arguments.values.count
                    ? "extra argument in call"
                    : "missing argument for parameter #\(arguments.values.count + 1) in call", at: node)
            return nil
        }
        guard let values = functionArguments(parameters, arguments) else { return nil }
        if effects.throwing { markThrows(at: callee) }
        if effects.async { markAwait(at: callee) }
        return Typed(.apply(value, values), result)
    }

    // MARK: Methods

    private func method(
        _ name: String, on baseSyntax: ExprSyntax, arguments: CallArguments, expecting expected: SwiftType?,
        at node: some SyntaxProtocol
    ) -> Typed? {
        guard let base = expression(baseSyntax, expecting: nil) else {
            unresolvedArguments(arguments)
            return nil
        }
        switch base.type {
        case .optional(let wrapped) where module.type(named: "Optional")?.methods[name] == nil:
            report(
                "value of optional type '\(base.type)' must be unwrapped to refer to member '\(name)' of wrapped base type '\(wrapped)'",
                at: node)
            return nil
        case .dynamic, .existential(["Actor"]):
            return message(name, to: base, declared: nil, arguments: arguments, at: node)
        case .unresolved:
            unresolvedArguments(arguments)
            return Typed(.read(base, name), .unresolved)
        default:
            break
        }
        // A requirement of the protocols the value is `any` of, as the value's own type meets it.
        if case .existential(let protocols) = base.type.unwrapped,
            case let requirements = requirements(name, of: protocols), !requirements.isEmpty
        {
            return witness(name, on: base, declared: requirements, arguments: arguments, at: node)
        }
        guard let declarationName = base.type.declarationName, let type = module.type(named: declarationName) else {
            report("value of type '\(base.type)' has no member '\(name)'", at: node)
            return nil
        }
        let candidates = instanceMethods(name, of: base.type)
        guard !candidates.isEmpty else {
            if instanceProperty(name, of: base.type) != nil {
                guard let value = member(name, of: base, at: node) else { return nil }
                return applyTyped(value, arguments: arguments, at: node)
            }
            report("value of type '\(base.type)' has no member '\(name)'", at: node)
            return nil
        }
        if isOtherActor(base, type) {
            return message(name, to: base, declared: candidates, arguments: arguments, at: node)
        }
        return methodCall(
            candidates, of: type, on: base, place: .expression(baseSyntax), arguments: arguments, expecting: expected,
            named: name, at: node)
    }

    private func applyTyped(_ value: Typed, arguments: CallArguments, at node: some SyntaxProtocol) -> Typed? {
        guard case .function(let parameters, let result, _) = value.type, parameters.count == arguments.values.count
        else {
            report("cannot call value of non-function type '\(value.type)'", at: node)
            return nil
        }
        guard let values = functionArguments(parameters, arguments) else { return nil }
        return Typed(.apply(value, values), result)
    }

    /// A function value's arguments, each as its parameter takes it: an `inout` one written
    /// `&place`, as the place.
    private func functionArguments(_ parameters: [SwiftType], _ arguments: CallArguments) -> [Argument]? {
        var values: [Argument] = []
        for (parameter, argument) in zip(parameters, arguments.values) {
            if case .inout(let wrapped) = parameter {
                guard let reference = argument.expression.as(InOutExprSyntax.self) else {
                    report(
                        "passing value of type '\(wrapped)' to an inout parameter requires explicit '&'",
                        at: argument.expression)
                    return nil
                }
                guard let (place, type) = place(reference.expression, mutating: nil) else { return nil }
                guard type == wrapped || type == .unresolved else {
                    report(
                        "cannot convert value of type '\(type)' to expected argument type '\(wrapped)'",
                        at: reference.expression)
                    return nil
                }
                values.append(.reference(place))
                continue
            }
            guard let resolved = expression(argument.expression, expecting: parameter),
                let converted = convert(resolved, to: parameter, at: argument.expression, as: .argument)
            else { return nil }
            values.append(.value(converted))
        }
        return values
    }

    /// Where a mutating method's value is: `self`, or the expression it's called on.
    enum Receiver {
        case selfPlace
        case expression(ExprSyntax)
        /// A place the code doesn't write, such as a `for await` loop's iterator.
        case place(Place)
    }

    func methodCall(
        _ candidates: [Function], of type: TypeDeclaration, on base: Typed, place receiver: Receiver,
        arguments: CallArguments,
        expecting expected: SwiftType?, named name: String, at node: some SyntaxProtocol
    ) -> Typed? {
        guard
            let (function, resolvedArguments, result) = applied(
                candidates, bindings: typeBindings(of: base.type), arguments: arguments, expecting: expected,
                named: name, at: node)
        else { return nil }
        if let unavailable = Self.unavailable(function) {
            report(unavailable, at: node)
            return nil
        }
        markEffects(of: function, arguments: resolvedArguments, at: node)
        let callee: Callee =
            if isNative(function) {
                .standard(StandardMember(type: type.name, member: function.written))
            } else if isStandard(function) || module.type(named: function.owner ?? "")?.kind == .protocol {
                .function(resolvedBody(of: function, for: base.type, generics: callBindings[Syntax(node).id] ?? [:]))
            } else { .function(resolvedBody(of: function)) }
        if function.isMutating {
            let place: Place
            switch receiver {
            case .selfPlace:
                guard context.mutatesSelf || type.kind == .actor else {
                    report("cannot use mutating member on immutable value: 'self' is immutable", at: node)
                    return nil
                }
                place = .stored(nil, index: -1)
            case .expression(let syntax):
                guard let (resolved, _) = self.place(syntax, mutating: name) else { return nil }
                place = resolved
            case .place(let given):
                place = given
            }
            return Typed(.mutating(place, callee, resolvedArguments), result)
        }
        switch callee {
        case .standard(let member): return Typed(.standard(member, on: base, resolvedArguments), result)
        case .function(let function): return Typed(.call(function, on: base, resolvedArguments), result)
        }
    }

    /// A message to another object: its method, as declared when it is, else by name, its answer
    /// read as whatever it is. It's asked, so it's awaited, and it can fail, so it's tried.
    /// The requirements called `name` of `protocols`, and of the protocols each refines.
    private func requirements(_ name: String, of protocols: [String]) -> [Function] {
        var seen: Set<String> = []
        var pending = protocols
        var found: [Function] = []
        while let next = pending.popLast() {
            guard seen.insert(next).inserted, let declaration = module.type(named: next), declaration.kind == .protocol
            else { continue }
            found += declaration.requirements.filter { $0.name == name }
            pending += declaration.refines
        }
        return found
    }

    /// A protocol's requirement called on `base`, a value of `any` of it: what it waits on and
    /// throws are the requirement's.
    private func witness(
        _ name: String, on base: Typed, declared: [Function], arguments: CallArguments, at node: some SyntaxProtocol
    ) -> Typed? {
        guard
            let (function, resolvedArguments, result) = applied(
                declared, bindings: [:], arguments: arguments, expecting: nil, named: name, at: node)
        else { return nil }
        if function.effects.async { markAwait(at: node) }
        if function.effects.throwing { markThrows(at: node) }
        let values = resolvedArguments.flatMap { argument -> [Typed] in
            switch argument {
            case .value(let value), .defaulted(let value): [value]
            case .variadic(let values): values
            case .reference: []
            }
        }
        return Typed(.witness(on: base, name, labels: function.parameters.map(\.label), values), result)
    }

    private func message(
        _ name: String, to base: Typed, declared: [Function]?, arguments: CallArguments, at node: some SyntaxProtocol
    ) -> Typed? {
        markAwait(at: node)
        guard let declared else {
            markThrows(at: node)
            var values: [Typed] = []
            for argument in arguments.values {
                guard let value = expression(argument.expression, expecting: nil) else { return nil }
                values.append(value)
            }
            return Typed(.message(to: base, name, labels: arguments.values.map(\.label), values), .dynamic)
        }
        guard
            let (function, resolvedArguments, result) = applied(
                declared, bindings: [:], arguments: arguments, expecting: nil, named: name, at: node)
        else { return nil }
        if function.effects.throwing { markThrows(at: node) }
        let values = resolvedArguments.flatMap { argument -> [Typed] in
            switch argument {
            case .value(let value), .defaulted(let value): [value]
            case .variadic(let values): values
            case .reference: []
            }
        }
        return Typed(.message(to: base, name, labels: function.parameters.map(\.label), values), result)
    }

    // MARK: Initializers

    func initializer(
        _ typeName: String, arguments: CallArguments, expecting expected: SwiftType?, at node: some SyntaxProtocol
    ) -> Typed? {
        // `Optional(value)` is its case `.some(value)`, as its initializer makes it.
        if typeName == "Optional" {
            guard case .optional(let wrapped)? = expected else {
                return optional("some", arguments: arguments, wrapping: nil, at: node)
            }
            return optional("some", arguments: arguments, wrapping: wrapped, at: node)
        }
        guard let type = module.type(named: typeName) else {
            report("cannot find '\(typeName)' in scope", at: node)
            return nil
        }
        var candidates = initializers(of: type)
        // Swift gives a type the initializer it makes only when its own body declares none: those
        // in extensions leave it.
        let declaresOwn = candidates.contains { $0.owner == typeName && !$0.isInExtension && $0.syntax != nil }
        switch type.kind {
        case .protocol:
            report("'any \(typeName)' cannot be constructed because it has no accessible initializers", at: node)
            return nil
        case .structure where !declaresOwn:
            candidates.append(memberwise(type))
        case .enumeration:
            if let raw = type.rawType {
                candidates.append(
                    Function(
                        name: "init",
                        parameters: [
                            Parameter(
                                label: "rawValue", name: "rawValue", type: raw, hasDefault: false, isVariadic: false,
                                isInout: false, defaultValue: nil)
                        ],
                        result: .optional(.named(typeName)), effects: .none, owner: typeName, syntax: nil))
            }
        case .actor where !declaresOwn:
            candidates.append(
                Function(
                    name: "init", parameters: [], result: .named(typeName), effects: .none, owner: typeName, syntax: nil
                ))
        default:
            break
        }
        guard !candidates.isEmpty else {
            report("'\(typeName)' cannot be constructed because it has no accessible initializers", at: node)
            return nil
        }
        var bindings = typeBindings(of: type.declaredType).filter { !$0.value.isOpen }
        // A type nested in a generic one, made inside it: the outer type's parameters are its own
        // there, as `Label(…)` inside `Box<Value>` is a `Box<Value>.Label`.
        if let selfType = context?.selfType, let dot = typeName.lastIndex(of: "."),
            case let outerName = String(typeName[..<dot]),
            selfType.name == outerName || selfType.name.hasPrefix(outerName + "."),
            let outer = module.type(named: outerName)
        {
            for name in outer.generics where bindings[name] == nil { bindings[name] = .parameter(name) }
        }
        guard
            let (function, resolvedArguments, result) = applied(
                candidates, bindings: bindings, arguments: arguments, expecting: expected,
                named: "init", at: node)
        else { return nil }
        markEffects(of: function, arguments: resolvedArguments, at: node)
        if type.kind == .standard {
            return Typed(
                .standard(StandardMember(type: typeName, member: function.written), on: nil, resolvedArguments), result)
        }
        if type.kind == .enumeration, function.syntax == nil, case .value(let raw)? = resolvedArguments.first {
            return Typed(.fromRawValue(typeName, raw), result)
        }
        // The standard library's own Swift is resolved for the type it makes, as its methods are.
        let body =
            function.syntax == nil
            ? nil : isStandard(function) ? resolvedBody(of: function, for: result) : resolvedBody(of: function)
        return Typed(.initialize(typeName, body, resolvedArguments), result)
    }

    /// A struct's memberwise initializer: its stored properties, in order, those with a value
    /// given it unless they're constants.
    private func memberwise(_ type: TypeDeclaration) -> Function {
        let parameters = type.stored.filter { $0.mutable || !$0.hasValue }.map { property in
            Parameter(
                label: property.name, name: property.name, type: propertyType(property, of: type),
                hasDefault: property.hasValue,
                isVariadic: false, isInout: false,
                defaultValue: property.syntax?.as(PatternBindingSyntax.self)?.initializer?.value)
        }
        // What it makes is the type with its generic parameters, as an initializer it declares makes.
        return Function(
            name: "init", parameters: parameters, result: type.declaredType, effects: .none, owner: type.name,
            syntax: nil)
    }

    // MARK: Applying arguments

    /// Which of `candidates` a call is to, and its arguments, each as its parameter takes it: the
    /// one the call's labels match, or of several, the first whose arguments convert.
    func applied(
        _ candidates: [Function], bindings: [String: SwiftType], arguments: CallArguments,
        expecting expected: SwiftType?,
        named name: String, at node: some SyntaxProtocol
    ) -> (Function, [Argument], SwiftType)? {
        let matching = candidates.compactMap { function in match(function.parameters, arguments).map { (function, $0) }
        }
        guard let first = matching.first else {
            reportMismatch(candidates[0], arguments, named: name, at: node)
            return nil
        }
        if matching.count > 1 {
            for (function, match) in matching
            where speculate({
                apply(function, match, bindings: bindings, arguments: arguments, expecting: expected, at: node)
            }) != nil {
                return apply(function, match, bindings: bindings, arguments: arguments, expecting: expected, at: node)
            }
        }
        return apply(first.0, first.1, bindings: bindings, arguments: arguments, expecting: expected, at: node)
    }

    enum Match {
        case given(Int)
        case defaulted
        case variadic([Int])
    }

    /// The arguments each parameter takes, by label and order, as Swift matches them; `nil` when
    /// they don't match.
    private func match(_ parameters: [Parameter], _ arguments: CallArguments) -> [Match]? {
        var matches: [Match] = []
        var index = 0
        let values = arguments.values
        for parameter in parameters {
            if parameter.isVariadic {
                var taken: [Int] = []
                while index < values.count,
                    taken.isEmpty ? values[index].label == parameter.label : values[index].label == nil
                {
                    taken.append(index)
                    index += 1
                }
                matches.append(.variadic(taken))
            } else if index < values.count,
                values[index].label == parameter.label
                    || (values[index].trailing && values[index].label == nil && Self.isFunction(parameter.type))
            {
                matches.append(.given(index))
                index += 1
            } else if parameter.hasDefault {
                matches.append(.defaulted)
            } else {
                return nil
            }
        }
        return index == values.count ? matches : nil
    }

    /// An expected type that a generic parameter isn't inferred from: `Any`, an existential, a
    /// message's answer, or what couldn't be decided.
    static func saysNothing(_ type: SwiftType) -> Bool {
        switch type.unwrapped {
        case .existential, .dynamic, .unresolved: true
        default: false
        }
    }

    private static func isFunction(_ type: SwiftType) -> Bool {
        if case .function = type.unwrapped { return true }
        return false
    }

    private func reportMismatch(
        _ function: Function, _ arguments: CallArguments, named name: String, at node: some SyntaxProtocol
    ) {
        let parameters = function.parameters.filter { !$0.hasDefault }
        let given = arguments.values
        if given.count > function.parameters.count {
            report("extra argument\(given.count - function.parameters.count > 1 ? "s" : "") in call", at: node)
        } else if given.count < parameters.count, let missing = parameters.dropFirst(given.count).first {
            report(
                "missing argument for parameter \(missing.label.map { "'\($0)'" } ?? "#\(given.count + 1)") in call",
                at: node)
        } else {
            let have = given.map { "\($0.label ?? "_"):" }.joined()
            let want = function.parameters.prefix(given.count).map { "\($0.label ?? "_"):" }.joined()
            report(
                "incorrect argument label\(given.count > 1 ? "s" : "") in call (have '\(have)', expected '\(want)')",
                at: node)
        }
    }

    private func apply(
        _ function: Function, _ matches: [Match], bindings initial: [String: SwiftType], arguments: CallArguments,
        expecting expected: SwiftType?, at node: some SyntaxProtocol
    ) -> (Function, [Argument], SwiftType)? {
        var bindings = initial
        // What a `where` fixes to a type is that type from the start: `Failure == any Error` before
        // any argument is read as what its parameter takes.
        for case .same(let parameter, let type) in function.requirements
        where !parameter.contains(".") && bindings[parameter] == nil && !type.substituting(bindings).isOpen {
            bindings[parameter] = type.substituting(bindings)
        }
        // An array literal given for a sequence whose elements a `where` fixes is an array of
        // them, as Swift types it: `Data([104, 105])` is given a `[UInt8]`.
        for (parameter, match) in zip(function.parameters, matches) {
            guard case .given(let index) = match, case .parameter(let name) = parameter.type, bindings[name] == nil,
                arguments.values[index].expression.is(ArrayExprSyntax.self),
                let element = function.requirements.lazy.compactMap({ requirement -> SwiftType? in
                    guard case .same("\(name).Element", let type) = requirement else { return nil }
                    return type.substituting(bindings)
                }).first, !element.isOpen
            else { continue }
            bindings[name] = .array(element)
        }
        // An expected existential says nothing of a generic result: it takes whatever's inferred.
        if let expected, function.result.substituting(bindings).isOpen, !Self.saysNothing(expected) {
            function.result.substituting(bindings).bind(to: expected, into: &bindings)
        }
        // Generic parameters bound by the arguments that aren't literals first, as Swift infers
        // them from all of a call's arguments: `max(0, amount)` is of `amount`'s type.
        for (parameter, match) in zip(function.parameters, matches) where parameter.type.substituting(bindings).isOpen {
            guard case .given(let index) = match, !Self.isLiteral(arguments.values[index].expression),
                !arguments.values[index].expression.is(ClosureExprSyntax.self)
            else { continue }
            let argument = arguments.values[index].expression
            if let value = speculate({ expression(argument, expecting: parameter.type.substituting(bindings)) }) {
                parameter.type.bind(to: value.type, into: &bindings)
            }
        }
        var resolved: [Argument] = []
        for (parameter, match) in zip(function.parameters, matches) {
            switch match {
            case .defaulted:
                guard let value = parameter.defaultValue,
                    let typed = within(
                        FunctionContext(
                            kind: .global, name: "default", selfType: nil, effects: .none, result: nil, parent: nil),
                        {
                            expression(value, expecting: parameter.type.substituting(bindings))
                        })
                else { return nil }
                resolved.append(.defaulted(converted(typed, to: parameter.type.substituting(bindings)) ?? typed))
            case .given(let index):
                let argument = arguments.values[index].expression
                if parameter.isInout {
                    guard let inOut = argument.as(InOutExprSyntax.self) else {
                        report(
                            "passing value of type '\(parameter.type)' to an inout parameter requires explicit '&'",
                            at: argument)
                        return nil
                    }
                    guard let (place, _) = place(inOut.expression, mutating: nil) else { return nil }
                    resolved.append(.reference(place))
                    continue
                }
                guard let value = argumentValue(argument, as: parameter.type, bindings: &bindings) else { return nil }
                resolved.append(.value(value))
            case .variadic(let indices):
                guard case .array(let element) = parameter.type else { return nil }
                var values: [Typed] = []
                for index in indices {
                    guard
                        let value = argumentValue(arguments.values[index].expression, as: element, bindings: &bindings)
                    else { return nil }
                    values.append(value)
                }
                resolved.append(.variadic(values))
            }
        }
        bindings = withAssociated(bindings)
        // What a `where` makes the same binds what's still open: `S.Element == Element`.
        for case .same(let parameter, let type) in function.requirements {
            let other = type.substituting(bindings)
            if let bound = bound(parameter, in: bindings), other.isOpen {
                other.bind(to: bound, into: &bindings)
            } else if !other.isOpen, !parameter.contains("."), bindings[parameter] == nil {
                bindings[parameter] = other
            }
        }
        let result = function.result.substituting(bindings)
        if result.isOpen(besides: context?.fixedParametersInScope ?? []) {
            report("generic parameter could not be inferred", at: node)
            return nil
        }
        for requirement in function.requirements {
            switch requirement {
            case .conforms(let parameter, let protocolName):
                guard let bound = bound(parameter, in: bindings) else { continue }
                if !conforms(bound, to: protocolName) {
                    report(
                        "referencing instance method '\(function.written)' requires that '\(bound)' conform to '\(protocolName)'",
                        at: node)
                    return nil
                }
            case .same(let parameter, let type):
                guard let bound = bound(parameter, in: bindings), bound != type.substituting(bindings) else { continue }
                report(
                    "referencing instance method '\(function.written)' requires the types '\(bound)' and '\(type)' be equivalent",
                    at: node)
                return nil
            }
        }
        callBindings[Syntax(node).id] = bindings
        return (function, resolved, result)
    }

    /// An argument, resolved as its parameter's type with what's bound so far, binding the rest.
    private func argumentValue(_ argument: ExprSyntax, as declared: SwiftType, bindings: inout [String: SwiftType])
        -> Typed?
    {
        bindings = withAssociated(bindings)
        let expected = declared.substituting(bindings)
        guard let value = expression(argument, expecting: expected) else { return nil }
        declared.bind(to: value.type, into: &bindings)
        return convert(value, to: declared.substituting(bindings), at: argument, as: .argument)
    }

    // MARK: Closures

    func closure(_ syntax: ClosureExprSyntax, expecting expected: SwiftType?) -> Typed? {
        var parameterTypes: [SwiftType]?
        var result: SwiftType?
        var expectedEffects: Effects?
        if case .function(let parameters, let declaredResult, let effects)? = expected?.unwrapped {
            parameterTypes = parameters
            result = declaredResult.isOpen ? nil : declaredResult
            expectedEffects = effects
        } else if expected == .unresolved {
            parameterTypes = nil
        } else if let expected, expected != .any, expected != .dynamic {
            report("cannot convert value of type closure to expected type '\(expected)'", at: syntax)
            return nil
        }
        var names: [String] = []
        var written: [SwiftType?] = []
        if let signature = syntax.signature {
            switch signature.parameterClause {
            case .simpleInput(let list)?:
                names = list.map(\.name.text)
                written = names.map { _ in nil }
            case .parameterClause(let clause)?:
                names = clause.parameters.map { ($0.secondName ?? $0.firstName).text }
                written = clause.parameters.map { $0.type.map { resolveWritten($0) } }
            case nil:
                break
            }
            if let returnClause = signature.returnClause { result = resolveWritten(returnClause.type) }
        } else {
            // `$0`, `$1`: as many as its type takes, or as it uses.
            let used = Self.anonymousParameters(in: syntax)
            names = (0..<max(parameterTypes?.count ?? 0, used)).map { "$\($0)" }
            written = names.map { _ in nil }
        }
        // A closure taking a pair's values as its parameters, as Swift lets one: `{ $1 - $0 }` for
        // a sequence of pairs.
        var unpacked: SwiftType?
        if let parameterTypes, parameterTypes.count == 1, case .tuple(let elements, _) = parameterTypes[0],
            names.count == elements.count,
            names.count > 1
        {
            unpacked = parameterTypes[0]
        }
        if let parameterTypes, unpacked == nil, parameterTypes.count != names.count,
            !(parameterTypes.count == 1 && names.isEmpty && parameterTypes[0] == .void)
        {
            if !(syntax.signature == nil && names.count < parameterTypes.count) {
                report(
                    "contextual closure type '\(expected!.unwrapped)' expects \(parameterTypes.count) argument\(parameterTypes.count == 1 ? "" : "s"), but \(names.count) \(names.count == 1 ? "was" : "were") used in closure body",
                    at: syntax)
                return nil
            }
        }
        var types: [SwiftType] = []
        let elementTypes: [SwiftType]? =
            if case .tuple(let elements, _)? = unpacked { elements } else { parameterTypes }
        for (index, name) in names.enumerated() {
            if let type = written[index] ?? elementTypes.flatMap({ index < $0.count ? $0[index] : nil }), !type.isOpen {
                types.append(type)
            } else if expected == .unresolved {
                types.append(.unresolved)
            } else {
                report("cannot infer type of closure parameter '\(name)' without a type annotation", at: syntax)
                return nil
            }
        }
        let closureContext = FunctionContext(
            kind: .closure, name: "closure", selfType: context.selfType, isStatic: context.isStatic,
            mutatesSelf: context.mutatesSelf,
            effects: .none, effectsInferred: true, result: result, parent: context)
        var unpacking: [Statement] = []
        if let unpacked {
            // The pair is its one parameter; each name is a value of it.
            let pair = closureContext.declare("$pair", type: unpacked, mutable: false)
            for (index, (name, type)) in zip(names, types).enumerated() {
                let slot = closureContext.declare(name, type: type, mutable: false)
                unpacking.append(
                    .declare(slot, Typed(.element(Typed(.local(Local(depth: 0, slot: pair)), unpacked), index), type)))
            }
        } else {
            // An `inout` parameter is a variable of its type, which the caller gets back.
            for (name, type) in zip(names, types) {
                if case .inout(let wrapped) = type {
                    _ = closureContext.declare(name, type: wrapped, mutable: true)
                } else {
                    _ = closureContext.declare(name, type: type, mutable: false)
                }
            }
        }
        let closure = Closure(parameters: unpacked == nil ? names.count : 1)
        let resultBefore = result
        closure.body =
            unpacking
            + within(closureContext) {
                let statements = syntax.statements
                if statements.count == 1, let only = statements.first, let value = only.item.as(ExprSyntax.self),
                    !Self.isAssignment(value),
                    !value.is(IfExprSyntax.self), !value.is(SwitchExprSyntax.self)
                {
                    guard let typed = expression(value, expecting: resultBefore == .void ? nil : resultBefore) else {
                        return []
                    }
                    if let declared = resultBefore {
                        if declared == .void { return [.expression(typed)] }
                        return convert(typed, to: declared, at: value, as: .returned).map { [.return($0)] } ?? []
                    }
                    closureContext.result = typed.type
                    return [.return(typed)]
                }
                return self.statements(statements)
            }
        closure.slots = closureContext.frame.slots
        let effects = Effects(async: closureContext.awaited, throwing: closureContext.threw)
        if let expectedEffects {
            if effects.async, !expectedEffects.async {
                report(
                    "cannot pass function of type '\(SwiftType.function(parameters: types, result: closureContext.result ?? .void, effects: effects))' to parameter expecting synchronous function type",
                    at: syntax)
                return nil
            }
            if effects.throwing, !expectedEffects.throwing {
                report(
                    "invalid conversion from throwing function of type '\(SwiftType.function(parameters: types, result: closureContext.result ?? .void, effects: effects))' to non-throwing function type",
                    at: syntax)
                return nil
            }
        }
        let parameters = unpacked.map { [$0] } ?? types
        return Typed(
            .closure(closure),
            .function(parameters: parameters, result: closureContext.result ?? .void, effects: effects))
    }

    private static func anonymousParameters(in closure: ClosureExprSyntax) -> Int {
        final class Finder: SyntaxVisitor {
            var highest = -1
            override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
                if case .dollarIdentifier(let name) = node.baseName.tokenKind, let index = Int(name.dropFirst()) {
                    highest = max(highest, index)
                }
                return .visitChildren
            }
            override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        }
        let finder = Finder(viewMode: .sourceAccurate)
        for statement in closure.statements { finder.walk(statement) }
        return finder.highest + 1
    }

    // MARK: Assignments

    func assignment(_ infix: InfixOperatorExprSyntax) -> Statement? {
        let left = infix.leftOperand
        let right = infix.rightOperand
        let op = infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text
        if left.is(DiscardAssignmentExprSyntax.self) {
            return expression(right, expecting: nil).map(Statement.expression)
        }
        // A standard type's property set without changing the value it's on: its setter, called on
        // the value, which needn't be a place.
        if op == nil, let member = left.as(MemberAccessExprSyntax.self), let baseSyntax = member.base,
            typeName(of: baseSyntax) == nil,
            let base = speculate({ expression(baseSyntax, expecting: nil) }),
            let typeName = base.type.declarationName, let type = module.type(named: typeName), type.kind == .standard,
            let (property, declaring) = instanceProperty(member.declName.baseName.text, of: base.type),
            property.isNonmutatingSet
        {
            guard let base = expression(baseSyntax, expecting: nil) else { return nil }
            let propertyType = propertyType(property, of: declaring).substituting(typeBindings(of: base.type))
            guard let value = expression(right, expecting: propertyType),
                let converted = convert(value, to: propertyType, at: right, as: .assigned)
            else { return nil }
            let setter = StandardMember(type: typeName, member: "\(property.name)=")
            return .expression(Typed(.standard(setter, on: base, [.value(converted)]), .void))
        }
        guard let (place, type) = place(left, mutating: nil) else {
            _ = expression(right, expecting: nil)
            return nil
        }
        guard let op else {
            guard let value = expression(right, expecting: type),
                let converted = convert(value, to: type, at: right, as: .assigned)
            else { return nil }
            return .assign(place, converted)
        }
        // `x += 1`: as `x = x + 1`, of the same type.
        let binary = String(op.dropLast())
        guard let value = expression(right, expecting: type) else { return nil }
        let operand = converted(value, to: type) ?? value
        switch (binary, type, operand.type) {
        case ("+", .string, .named("Substring", _)), ("+", .named("Substring", _), .string):
            return .compound(place, binary, operand)
        case ("+", .string, .string), ("+", .array, .array), (_, .int, .int), ("+", .double, .double),
            ("-", .double, .double),
            ("*", .double, .double), ("/", .double, .double):
            return .compound(place, binary, operand)
        case (let binary, .fixedInteger(let kind), .fixedInteger(let other))
        where kind == other || binary == "<<" || binary == ">>":
            return .compound(place, binary, operand)
        case ("<<", .int, let amount) where amount.isInteger,
            (">>", .int, let amount) where amount.isInteger:
            return .compound(place, binary, operand)
        default:
            report(
                "binary operator '\(op)' cannot be applied to operands of type '\(type)' and '\(value.type)'",
                at: infix.operator)
            return nil
        }
    }

    /// What an assignment writes, with its type, when it can be written: a `var`, a constant given
    /// its value the first time, a property of `self` that may change, or a part of one of them.
    func place(_ expr: ExprSyntax, mutating method: String?) -> (Place, SwiftType)? {
        let immutable: (String, String) -> String = { name, what in
            method.map { _ in "cannot use mutating member on immutable value: '\(name)' is a \(what)" }
                ?? "cannot assign to value: '\(name)' is a \(what)"
        }
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if let (binding, depth) = context.lookup(name) {
                let local = Local(depth: binding.frameDepth, slot: binding.slot)
                if context.unassigned.contains(local) {
                    guard method == nil else {
                        report(
                            "\(binding.mutable ? "variable" : "constant") '\(name)' used before being initialized",
                            at: reference)
                        return nil
                    }
                    context.unassigned.remove(local)
                } else if !binding.mutable {
                    report(immutable(name, "'let' constant"), at: reference)
                    return nil
                }
                return (.local(Local(depth: depth, slot: binding.slot)), binding.type)
            }
            if name == "self" {
                guard context.mutatesSelf else {
                    report("cannot assign to value: 'self' is immutable", at: reference)
                    return nil
                }
                // As `self` is where it's used: `Result<Int, any Error>` for the standard library's code.
                return context.selfType.map {
                    (.stored(nil, index: -1), context.selfValueTypeInScope ?? $0.declaredType)
                }
            }
            if let selfType = context.selfType, let property = selfType.properties[name] {
                return selfProperty(property, of: selfType, at: reference, method: method)
            }
            if let global = module.globals[name] {
                guard global.mutable else {
                    report(immutable(name, "'let' constant"), at: reference)
                    return nil
                }
                return globalType(name).map { (.global(name), $0) }
            }
            report("cannot find '\(name)' in scope", at: reference)
            return nil
        }
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base {
            let name = member.declName.baseName.text
            if base.as(DeclReferenceExprSyntax.self)?.baseName.text == "self", let selfType = context.selfType,
                context.lookup("self") == nil, let property = selfType.properties[name]
            {
                return selfProperty(property, of: selfType, at: member.declName, method: method)
            }
            // A stored property of a struct value that's itself a place.
            guard let (basePlace, baseType) = place(base, mutating: method == nil ? "" : method) else { return nil }
            guard case .named(let typeName, _) = baseType, let type = module.type(named: typeName),
                type.kind == .structure,
                let property = type.properties[name], let index = type.stored.firstIndex(where: { $0.name == name })
            else {
                report("cannot assign to property: '\(name)' is not settable", at: member.declName)
                return nil
            }
            guard property.mutable else {
                report("cannot assign to property: '\(name)' is a 'let' constant", at: member.declName)
                return nil
            }
            return (.stored(basePlace, index: index), propertyType(property, of: type))
        }
        if let subscriptCall = expr.as(SubscriptCallExprSyntax.self) {
            guard let (basePlace, baseType) = place(subscriptCall.calledExpression, mutating: method ?? "subscript")
            else { return nil }
            guard let declarationName = baseType.declarationName, module.type(named: declarationName) != nil,
                case let candidates = instanceMethods("subscript", of: baseType), !candidates.isEmpty
            else {
                report("value of type '\(baseType)' has no subscripts", at: subscriptCall)
                return nil
            }
            let arguments = CallArguments(subscriptCall.arguments, trailing: nil)
            guard
                let (function, resolvedArguments, result) = applied(
                    candidates, bindings: typeBindings(of: baseType), arguments: arguments, expecting: nil,
                    named: "subscript", at: subscriptCall)
            else { return nil }
            return (
                .subscripted(
                    basePlace, by: resolvedArguments.compactMap(\.typed),
                    getter: StandardMember(type: declarationName, member: function.written)), result
            )
        }
        if let force = expr.as(ForceUnwrapExprSyntax.self) {
            guard let (basePlace, baseType) = place(force.expression, mutating: method) else { return nil }
            guard case .optional(let wrapped) = baseType else {
                report("cannot force unwrap value of non-optional type '\(baseType)'", at: force.exclamationMark)
                return nil
            }
            return (.optional(basePlace), wrapped)
        }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first {
            return place(only.expression, mutating: method)
        }
        report("cannot assign to this expression", at: expr)
        return nil
    }

    private func selfProperty(
        _ property: Property, of type: TypeDeclaration, at node: some SyntaxProtocol, method: String?
    ) -> (Place, SwiftType)? {
        let propertyType = propertyType(property, of: type)
        guard property.isStored, let index = type.stored.firstIndex(where: { $0.name == property.name }) else {
            if property.mutable { return (.stored(nil, index: -1), propertyType) }
            report("cannot assign to property: '\(property.name)' is a get-only property", at: node)
            return nil
        }
        if context.kind == .initializer, context.unassignedStored.contains(property.name) {
            if method == nil { context.unassignedStored.remove(property.name) }
            return (.stored(nil, index: index), propertyType)
        }
        guard property.mutable else {
            report(
                method.map { _ in
                    "cannot use mutating member on immutable value: '\(property.name)' is a 'let' constant"
                }
                    ?? "cannot assign to property: '\(property.name)' is a 'let' constant", at: node)
            return nil
        }
        guard type.kind == .actor || context.mutatesSelf else {
            report(
                method.map { _ in "cannot use mutating member on immutable value: 'self' is immutable" }
                    ?? "cannot assign to property: 'self' is immutable", at: node)
            return nil
        }
        return (.stored(nil, index: index), propertyType)
    }
}
