import Doppel

/// Runs a resolved file: a fold over its resolved tree, which says what every name is and every
/// value's type, so nothing is looked up or inferred here. What the file's given is the host's.
package final class Evaluator {
    let program: ResolvedProgram
    let host: any ActorHost
    /// The module the code is in, as Swift names its types when it writes them in a collection.
    let module: String
    /// The values the code threw, by the number each was thrown as, until they're caught.
    private var thrownValues: [Int: Value] = [:]
    private var nextThrown = 0
    /// The tasks the code started, by number, until they run.
    private var tasks: [Int: FunctionValue] = [:]
    private var nextTask = 1
    /// Globals, once made: the file's own, and the host's.
    var globalValues: [String: Value] = [:]

    init(program: ResolvedProgram, host: any ActorHost, module: String) {
        self.program = program
        self.host = host
        self.module = module
    }

    /// How a statement ends: going on, returning, or leaving its loop.
    enum Flow {
        case next
        case returned(Value)
        case broke
        case continued
    }

    // MARK: Functions

    /// A function of the file's run, on `self` when it's a method, with its arguments.
    func run(_ function: ResolvedFunction, on receiver: Value?, arguments: [Value]) async throws -> Value {
        let frame = Frame(slots: max(function.slots, arguments.count), parent: nil, selfValue: receiver)
        for (index, argument) in arguments.enumerated() { frame.slots[index] = argument }
        return try await body(function.body, in: frame)
    }

    func call(_ closure: FunctionValue, _ arguments: [Value]) async throws -> Value {
        try await callKeepingFrame(closure, arguments).0
    }

    /// A closure called, with the frame it ran in: its parameters' values at the end.
    func callKeepingFrame(_ closure: FunctionValue, _ arguments: [Value]) async throws -> (Value, Frame) {
        let frame = Frame(slots: max(closure.closure.slots, arguments.count), parent: closure.frame, selfValue: nil)
        for (index, argument) in arguments.enumerated() { frame.slots[index] = argument }
        return (try await body(closure.closure.body, in: frame), frame)
    }

    private func body(_ statements: [Statement], in frame: Frame) async throws -> Value {
        // A body's `defer`s run in reverse, however it ends.
        var deferred: [[Statement]] = []
        do {
            let flow = try await run(statements, in: frame, deferring: &deferred)
            for body in deferred.reversed() { _ = try await run(body, in: frame) }
            if case .returned(let value) = flow { return value }
            return .void
        } catch {
            for body in deferred.reversed() { _ = try? await run(body, in: frame) }
            throw error
        }
    }

    /// The task the code started as `id`, run.
    func runTask(_ id: Int) async throws {
        guard let task = tasks.removeValue(forKey: id) else { return }
        _ = try await call(task, [])
    }

    // MARK: Statements

    func run(_ statements: [Statement], in frame: Frame) async throws -> Flow {
        var deferred: [[Statement]] = []
        let flow = try await run(statements, in: frame, deferring: &deferred)
        for body in deferred.reversed() { _ = try await run(body, in: frame) }
        return flow
    }

    private func run(_ statements: [Statement], in frame: Frame, deferring deferred: inout [[Statement]]) async throws
        -> Flow
    {
        for statement in statements {
            let flow = try await run(statement, in: frame, deferring: &deferred)
            if case .next = flow { continue }
            return flow
        }
        return .next
    }

    private func run(_ statement: Statement, in frame: Frame, deferring deferred: inout [[Statement]]) async throws
        -> Flow
    {
        switch statement {
        case .at(let line, let inner):
            do {
                return try await run(inner, in: frame, deferring: &deferred)
            } catch let trap as Trap where trap.line == nil {
                throw Trap(message: trap.message, line: line)
            }
        case .expression(let value):
            _ = try await evaluate(value, in: frame)
        case .declare(let slot, let value):
            if let value { frame.slots[slot] = try await evaluate(value, in: frame) }
        case .assign(let place, let value):
            let new = try await evaluate(value, in: frame)
            try await write(place, new, in: frame)
        case .compound(let place, let op, let value):
            let current = try await read(place, in: frame)
            let operand = try await evaluate(value, in: frame)
            try await write(place, try binary(op, current, operand), in: frame)
        case .if(let branches, let otherwise):
            for branch in branches {
                let scope = frame
                if try await holds(branch.conditions, in: scope) { return try await run(branch.body, in: frame) }
            }
            if let otherwise { return try await run(otherwise, in: frame) }
        case .guard(let conditions, let otherwise):
            if try await !holds(conditions, in: frame) { return try await run(otherwise, in: frame) }
        case .while(let conditions, let body):
            while try await holds(conditions, in: frame) {
                switch try await run(body, in: frame) {
                case .broke: return .next
                case .returned(let value): return .returned(value)
                case .next, .continued: continue
                }
            }
        case .repeatWhile(let body, let condition):
            repeat {
                switch try await run(body, in: frame) {
                case .broke: return .next
                case .returned(let value): return .returned(value)
                case .next, .continued: break
                }
            } while try await truth(condition, in: frame)
        case .forIn(let pattern, let sequence, let body):
            for element in try elements(of: try await evaluate(sequence, in: frame)) {
                guard try await matches(pattern, element, in: frame) else { continue }
                switch try await run(body, in: frame) {
                case .broke: return .next
                case .returned(let value): return .returned(value)
                case .next, .continued: continue
                }
            }
        case .switch(let subject, let cases):
            let value = try await evaluate(subject, in: frame)
            for switchCase in cases {
                var matched = false
                for pattern in switchCase.patterns where try await matches(pattern, value, in: frame) {
                    matched = true
                    break
                }
                guard matched else { continue }
                if let guarded = switchCase.guard, try await !truth(guarded, in: frame) { continue }
                let flow = try await run(switchCase.body, in: frame)
                if case .broke = flow { return .next }
                return flow
            }
        case .return(let value):
            guard let value else { return .returned(.void) }
            return .returned(try await evaluate(value, in: frame))
        case .throw(let value):
            throw try thrown(try await evaluate(value, in: frame))
        case .break:
            return .broke
        case .continue:
            return .continued
        case .defer(let body):
            deferred.append(body)
        case .block(let body):
            return try await run(body, in: frame)
        case .doCatch(let body, let errorSlot, let catches):
            do {
                return try await run(body, in: frame)
            } catch let trap as Trap {
                throw trap
            } catch {
                // What was thrown here is the value thrown; another object's failure, its words.
                let value: Value =
                    (error as? Thrown).flatMap { thrownValues.removeValue(forKey: $0.id) } ?? .string("\(error)")
                frame.slots[errorSlot] = value
                for clause in catches {
                    if let pattern = clause.pattern, try await !matches(pattern, value, in: frame) { continue }
                    return try await run(clause.body, in: frame)
                }
                throw error
            }
        }
        return .next
    }

    private func holds(_ conditions: [Condition], in frame: Frame) async throws -> Bool {
        for condition in conditions {
            switch condition {
            case .boolean(let value):
                guard try await truth(value, in: frame) else { return false }
            case .bind(let slot, let value):
                guard case .optional(let wrapped?) = try await evaluate(value, in: frame) else { return false }
                frame.slots[slot] = wrapped
            case .matches(let pattern, let value):
                guard try await matches(pattern, try await evaluate(value, in: frame), in: frame) else { return false }
            }
        }
        return true
    }

    func truth(_ value: Typed, in frame: Frame) async throws -> Bool {
        guard case .bool(let flag) = try await evaluate(value, in: frame) else {
            throw Trap(message: "a condition isn't a Bool")
        }
        return flag
    }

    private func matches(_ pattern: Pattern, _ value: Value, in frame: Frame) async throws -> Bool {
        switch pattern {
        case .wildcard:
            return true
        case .bind(let slot):
            frame.slots[slot] = value
            return true
        case .value(let expected):
            return try Self.equal(value, try await evaluate(expected, in: frame))
        case .enumCase(let name, let patterns):
            guard case .enumCase(_, let caseName, let values) = value, caseName == name else { return false }
            for (pattern, value) in zip(patterns, values) where try await !matches(pattern, value, in: frame) {
                return false
            }
            return true
        case .tuple(let patterns):
            guard case .tuple(let values) = value else { return false }
            for (pattern, value) in zip(patterns, values) where try await !matches(pattern, value, in: frame) {
                return false
            }
            return true
        case .some(let inner):
            guard case .optional(let wrapped?) = value else { return false }
            return try await matches(inner, wrapped, in: frame)
        }
    }

    /// A sequence's elements, in order: an array's, a set's, a string's characters, a
    /// dictionary's pairs, data's bytes.
    func elements(of sequence: Value) throws -> [Value] {
        switch sequence {
        case .array(let elements), .set(let elements): return elements
        case .string(let text): return text.map(Value.character)
        case .dictionary(let pairs): return pairs.map { .tuple([$0.key, $0.value]) }
        case .data(let bytes): return bytes.map(Self.byte)
        default: throw Trap(message: "a for-in loop's sequence isn't one")
        }
    }

    // MARK: Expressions

    func evaluate(_ typed: Typed, in frame: Frame) async throws -> Value {
        switch typed.expression {
        case .integer(let number): return .int(number)
        case .fixedInteger(let kind, let bits): return .fixed(kind, bits)
        case .range(let lower, let upper, let closed):
            let (low, high) = (try await evaluate(lower, in: frame), try await evaluate(upper, in: frame))
            guard try Self.compare(low, high) <= 0 else {
                throw Trap(message: "Range requires lowerBound <= upperBound")
            }
            return .structure(closed ? "ClosedRange" : "Range", [low, high])
        case .double(let number): return .double(number)
        case .string(let text): return .string(text)
        case .character(let character): return .character(character)
        case .bool(let flag): return .bool(flag)
        case .nil: return .optional(nil)
        case .interpolation(let pieces):
            var text = ""
            for piece in pieces {
                switch piece {
                case .text(let literal): text += literal
                case .value(let value): text += describe(try await evaluate(value, in: frame))
                }
            }
            return .string(text)
        case .local(let local):
            return frame.frame(local.depth).slots[local.slot]
        case .selfValue:
            return frame.selfFrame.selfValue ?? .void
        case .metatype(let type):
            return .metatype(type)
        case .global(let name):
            return try await global(name, as: typed.type)
        case .stored(let base, let index):
            return try field(index, of: try await evaluate(base, in: frame))
        case .computed(let base, let getter):
            return try await run(getter, on: try await evaluate(base, in: frame), arguments: [])
        case .call(let function, let receiver, let arguments):
            let values = try await self.arguments(arguments, in: frame)
            if !program.runsHere(function.declaration.syntax) {
                return try await hostCall(
                    function.declaration.qualifiedName, function.declaration.parameters.map(\.label), values,
                    function.declaration.parameters.map(\.type), answering: typed.type)
            }
            var base: Value?
            if let receiver { base = try await evaluate(receiver, in: frame) }
            return try await run(function, on: base, arguments: values)
        case .standard(let member, let receiver, let arguments):
            var base: Value?
            if let receiver { base = try await evaluate(receiver, in: frame) }
            return try await standard(member, on: base, try await self.arguments(arguments, in: frame), as: typed.type)
        case .mutating(let place, let callee, let arguments):
            let values = try await self.arguments(arguments, in: frame)
            var value = try await read(place, in: frame)
            let result: Value
            switch callee {
            case .standard(let member): result = try await mutating(member, &value, values)
            case .function(let function):
                let methodFrame = Frame(slots: max(function.slots, values.count), parent: nil, selfValue: value)
                for (index, argument) in values.enumerated() { methodFrame.slots[index] = argument }
                result = try await body(function.body, in: methodFrame)
                value = methodFrame.selfValue ?? value
            }
            try await write(place, value, in: frame)
            return result
        case .initialize(let typeName, let initializer, let arguments):
            return try await make(typeName, initializer, try await self.arguments(arguments, in: frame))
        case .enumCase(let typeName, let caseName, let values):
            var made: [Value] = []
            for value in values { made.append(try await evaluate(value, in: frame)) }
            return .enumCase(typeName, caseName, made)
        case .message(let receiver, let name, let labels, let values):
            guard case .object(let handle) = try await evaluate(receiver, in: frame) else {
                throw Trap(message: "'\(name)' sent to what isn't an object")
            }
            var arguments: [(label: String?, value: Portable)] = []
            for (label, value) in zip(labels, values) {
                arguments.append((label, try portable(try await evaluate(value, in: frame), as: value.type)))
            }
            return try value(
                try await host.send(name, to: handle, through: messageType(receiver.type), arguments: arguments),
                as: typed.type)
        case .witness(let receiver, let name, let labels, let values):
            let base = try await evaluate(receiver, in: frame)
            var evaluated: [Value] = []
            for value in values { evaluated.append(try await evaluate(value, in: frame)) }
            // Another object meets it itself: the call is a message to it, through the protocol.
            if case .object(let handle) = base {
                var arguments: [(label: String?, value: Portable)] = []
                for (label, (value, typed)) in zip(labels, zip(evaluated, values)) {
                    arguments.append((label, try portable(value, as: typed.type)))
                }
                return try self.value(
                    try await host.send(name, to: handle, through: messageType(receiver.type), arguments: arguments),
                    as: typed.type)
            }
            // A value of this code's own types meets it with its type's method.
            let concrete: String? =
                switch base {
                case .structure(let type, _), .enumCase(let type, _, _): type
                case .actor(let instance): instance.type
                default: nil
                }
            guard let concrete,
                let method = program.type(named: concrete)?.method(name).first(where: {
                    $0.parameters.map(\.label) == labels
                })
            else { throw Trap(message: "'\(name)' isn't taken by the value it's called on") }
            return try await run(program.body(of: method), on: base, arguments: evaluated)
        case .read(let receiver, let name):
            guard case .object(let handle) = try await evaluate(receiver, in: frame) else {
                throw Trap(message: "'\(name)' read of what isn't an object")
            }
            return try value(try await host.read(name, of: handle), as: typed.type)
        case .array(let elements):
            var values: [Value] = []
            for element in elements { values.append(try await evaluate(element, in: frame)) }
            return .array(values)
        case .dictionary(let pairs):
            var values: [(key: Value, value: Value)] = []
            for (key, value) in pairs {
                let k = try await evaluate(key, in: frame)
                let v = try await evaluate(value, in: frame)
                if let index = try values.firstIndex(where: { try Self.equal($0.key, k) }) {
                    values[index].value = v
                } else {
                    values.append((k, v))
                }
            }
            return .dictionary(values)
        case .tuple(let elements):
            var values: [Value] = []
            for element in elements { values.append(try await evaluate(element, in: frame)) }
            return elements.isEmpty ? .void : .tuple(values)
        case .element(let base, let index):
            guard case .tuple(let values) = try await evaluate(base, in: frame), index < values.count else {
                throw Trap(message: "not a tuple")
            }
            return values[index]
        case .closure(let closure):
            return .function(FunctionValue(closure: closure, frame: frame))
        case .apply(let function, let arguments):
            guard case .function(let closure) = try await evaluate(function, in: frame) else {
                throw Trap(message: "not a function")
            }
            var values: [Value] = []
            var references: [(slot: Int, place: Place)] = []
            for (index, argument) in arguments.enumerated() {
                switch argument {
                case .reference(let place):
                    values.append(try await read(place, in: frame))
                    references.append((index, place))
                default:
                    values.append(contentsOf: try await self.arguments([argument], in: frame))
                }
            }
            // An `inout` parameter's value at the end is what the caller's place becomes.
            let (result, closureFrame) = try await callKeepingFrame(closure, values)
            for reference in references {
                try await write(reference.place, closureFrame.slots[reference.slot], in: frame)
            }
            return result
        case .unary(let op, let operand):
            let value = try await evaluate(operand, in: frame)
            switch (op, value) {
            case ("!", .bool(let flag)): return .bool(!flag)
            case ("-", .double(let number)): return .double(-number)
            case (_, .int), (_, .fixed):
                guard let integer = Integer(value) else { break }
                return try integerUnary(op, integer)
            default: break
            }
            throw Trap(message: "'\(op)' can't be applied here")
        case .binary(let op, let lhs, let rhs):
            return try binary(op, try await evaluate(lhs, in: frame), try await evaluate(rhs, in: frame))
        case .and(let lhs, let rhs):
            return .bool(try await truth(lhs, in: frame) ? try await truth(rhs, in: frame) : false)
        case .or(let lhs, let rhs):
            return .bool(try await truth(lhs, in: frame) ? true : try await truth(rhs, in: frame))
        case .ternary(let condition, let then, let otherwise):
            return try await evaluate(try await truth(condition, in: frame) ? then : otherwise, in: frame)
        case .coalesce(let lhs, let rhs):
            if case .optional(let wrapped?) = try await evaluate(lhs, in: frame) {
                if case .optional = rhs.type { return .optional(wrapped) }
                return wrapped
            }
            return try await evaluate(rhs, in: frame)
        case .force(let value):
            switch try await evaluate(value, in: frame) {
            case .optional(let wrapped?): return wrapped
            case .optional(nil): throw Trap(message: "Unexpectedly found nil while unwrapping an Optional value")
            case let other: return other
            }
        case .chain(let base, let rest):
            guard case .optional(let wrapped?) = try await evaluate(base, in: frame) else { return .optional(nil) }
            chained.append(wrapped)
            defer { chained.removeLast() }
            let value = try await evaluate(rest, in: frame)
            if case .optional = rest.type { return value }
            return .optional(value)
        case .chained:
            guard let value = chained.last else { throw Trap(message: "an optional chain's value is missing") }
            return value
        case .wrap(let value):
            return .optional(try await evaluate(value, in: frame))
        case .erase(let value):
            return try await evaluate(value, in: frame)
        case .await(let value), .try(let value):
            return try await evaluate(value, in: frame)
        case .tryOptional(let value):
            do {
                let result = try await evaluate(value, in: frame)
                if case .optional = value.type { return result }
                return .optional(result)
            } catch let trap as Trap {
                throw trap
            } catch {
                return .optional(nil)
            }
        case .tryForce(let value):
            do {
                return try await evaluate(value, in: frame)
            } catch let trap as Trap {
                throw trap
            } catch {
                throw Trap(message: "'try!' expression unexpectedly raised an error: \(error)")
            }
        case .cast(let value, let type, let kind):
            return try await cast(try await evaluate(value, in: frame), from: value.type, to: type, kind)
        case .assignment(let place, let value):
            try await write(place, try await evaluate(value, in: frame), in: frame)
            return .void
        case .rawValue(let value):
            guard case .enumCase(let typeName, let caseName, _) = try await evaluate(value, in: frame),
                let raw = rawValue(of: typeName, caseName)
            else {
                throw Trap(message: "no raw value")
            }
            return raw
        case .fromRawValue(let typeName, let raw):
            let given = try await evaluate(raw, in: frame)
            guard let declaration = program.type(named: typeName) else { return .optional(nil) }
            for caseName in declaration.caseNames {
                if let value = rawValue(of: typeName, caseName), try Self.equal(value, given) {
                    return .optional(.enumCase(typeName, caseName, []))
                }
            }
            return .optional(nil)
        }
    }

    /// The values the optional chains being evaluated read, innermost last.
    private var chained: [Value] = []

    private func arguments(_ arguments: [Argument], in frame: Frame) async throws -> [Value] {
        var values: [Value] = []
        for argument in arguments {
            switch argument {
            case .value(let value), .defaulted(let value): values.append(try await evaluate(value, in: frame))
            case .variadic(let elements):
                var made: [Value] = []
                for element in elements { made.append(try await evaluate(element, in: frame)) }
                values.append(.array(made))
            case .reference(let place): values.append(try await read(place, in: frame))
            }
        }
        return values
    }

    // MARK: The host's

    private func global(_ name: String, as type: SwiftType) async throws -> Value {
        if let made = globalValues[name] { return made }
        guard let initial = program.global(name) else {
            // A type used as a value: its static members' base.
            return .void
        }
        let value = try await evaluate(initial, in: Frame(slots: 16, parent: nil, selfValue: nil))
        globalValues[name] = value
        return value
    }

    /// The actor type a message is sent through: the declared actor its receiver is, `nil` for any
    /// object.
    private func messageType(_ type: SwiftType) -> String? {
        switch type {
        case .named(let name, _) where program.type(named: name)?.isActor == true: name
        // An object held as conforming to a protocol, as code writes it: `any Shop.RefundManager`.
        case .existential(let protocols)
        where protocols.count == 1 && program.type(named: protocols[0])?.kind == .protocol:
            "any \(protocols[0])"
        case .optional(let wrapped): messageType(wrapped)
        default: nil
        }
    }

    private func hostCall(
        _ name: String, _ labels: [String?], _ values: [Value], _ types: [SwiftType], answering type: SwiftType
    ) async throws -> Value {
        var arguments: [(label: String?, value: Portable)] = []
        for (index, value) in values.enumerated() {
            arguments.append(
                (
                    index < labels.count ? labels[index] : nil,
                    try portable(value, as: index < types.count ? types[index] : .dynamic)
                ))
        }
        return try value(try await host.call(name, arguments: arguments), as: type)
    }

    // MARK: Types

    /// A value of a type made: the file's struct, by its initializer or memberwise; the actor that
    /// runs, by its initializer, once; and any other actor, which is another object, by the host.
    func make(_ typeName: String, _ initializer: ResolvedFunction?, _ arguments: [Value], itself: Bool = false)
        async throws -> Value
    {
        guard let declaration = program.type(named: typeName) else { throw Trap(message: "no type '\(typeName)'") }
        if declaration.isActor, !itself {
            let parameters = initializer?.declaration.parameters ?? []
            var given: [(label: String?, value: Portable)] = []
            for (index, value) in arguments.enumerated() {
                let parameter = index < parameters.count ? parameters[index] : nil
                given.append((parameter?.label, try portable(value, as: parameter?.type ?? .dynamic)))
            }
            return .object(try await host.make(typeName, arguments: given))
        }
        var fields: [Value] = []
        for (index, name) in declaration.storedNames.enumerated() {
            let property = declaration.storedProperty(index)
            if let value = program.startingValue(of: property, in: declaration) {
                fields.append(
                    try await evaluate(value.value, in: Frame(slots: value.slots, parent: nil, selfValue: nil)))
            } else if case .optional = program.storedType(of: declaration, at: index), property.mutable {
                fields.append(.optional(nil))
            } else {
                _ = name
                fields.append(.void)
            }
        }
        if declaration.isActor {
            let instance = ActorInstance(type: typeName, fields: fields)
            if let initializer { _ = try await run(initializer, on: .actor(instance), arguments: arguments) }
            return .actor(instance)
        }
        guard let initializer else {
            // Memberwise: each argument for the stored property it's named for, in order.
            let parameters = declaration.memberwiseFields
            for (field, value) in zip(parameters, arguments) { fields[field] = value }
            return .structure(typeName, fields)
        }
        let frame = Frame(
            slots: max(initializer.slots, arguments.count), parent: nil, selfValue: .structure(typeName, fields))
        for (index, argument) in arguments.enumerated() { frame.slots[index] = argument }
        _ = try await body(initializer.body, in: frame)
        return frame.selfValue ?? .structure(typeName, fields)
    }

    func field(_ index: Int, of value: Value) throws -> Value {
        switch value {
        case .actor(let instance): return instance.fields[index]
        case .structure(_, let fields): return fields[index]
        default: throw Trap(message: "not a value with properties")
        }
    }

    func fieldType(_ declaration: TypeDeclaration, _ index: Int) -> SwiftType {
        program.storedType(of: declaration, at: index)
    }

    func rawValue(of typeName: String, _ caseName: String) -> Value? {
        guard let declaration = program.type(named: typeName) else { return nil }
        switch program.rawValue(of: declaration, case: caseName) {
        case .int(let number)?: return .int(number)
        case .double(let number)?: return .double(number)
        case .string(let text)?: return .string(text)
        case nil: return nil
        }
    }

    /// `value` thrown, as a `throw` throws it: whoever catches it in the same code gets it back.
    func thrown(_ value: Value) throws -> Thrown {
        nextThrown += 1
        thrownValues[nextThrown] = value
        return Thrown(type: Self.typeName(of: value), value: try portable(value, as: .dynamic), id: nextThrown)
    }

    // MARK: Tasks

    func startTask(_ operation: Value) -> Value {
        guard case .function(let closure) = operation else { return .void }
        let id = nextTask
        nextTask += 1
        tasks[id] = closure
        host.schedule(task: id)
        return .task(TaskHandle(id: id))
    }

    func cancelTask(_ task: Value) {
        guard case .task(let handle) = task else { return }
        tasks[handle.id] = nil
        host.cancel(task: handle.id)
    }
}
