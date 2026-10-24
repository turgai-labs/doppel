/// A module's code, resolved: every name to what it is, every expression to its type, every
/// implicit conversion made explicit. What runs is this, not the syntax: nothing is looked up or
/// inferred while it runs.
package struct ResolvedModule {
    package var types: [String: ResolvedType] = [:]
    /// Global constants, with their values, in the order they're declared.
    package var globals: [(name: String, value: Typed)] = []
}

package struct ResolvedType {
    package let name: String
    package let kind: TypeDeclaration.Kind
    /// Its stored properties, in order, each with its starting value if it has one.
    package var stored: [(name: String, value: Typed?)] = []
    package var methods: [String: [ResolvedFunction]] = [:]
    package var initializers: [ResolvedFunction] = []
}

/// A function's body, resolved: its parameters are its first slots, and its locals the rest.
package final class ResolvedFunction {
    package let declaration: Function
    package var body: [Statement] = []
    /// How many locals it has, parameters included.
    package var slots = 0

    init(_ declaration: Function) { self.declaration = declaration }
}

/// A local's place: `depth` frames out from the one running, `slot` in that frame. A closure's
/// frame's parent is the frame it was made in.
package struct Local: Hashable {
    package let depth: Int
    package let slot: Int
}

package indirect enum Statement {
    /// A statement at the line it's written on, which a failure while it runs is at.
    case at(line: Int, Statement)
    case expression(Typed)
    /// A local, given its value now, or later.
    case declare(Int, Typed?)
    case assign(Place, Typed)
    case compound(Place, String, Typed)
    case `if`(branches: [(conditions: [Condition], body: [Statement])], otherwise: [Statement]?)
    case `guard`([Condition], otherwise: [Statement])
    case `while`([Condition], body: [Statement])
    case repeatWhile(body: [Statement], condition: Typed)
    case forIn(Pattern, sequence: Typed, body: [Statement])
    case `switch`(Typed, cases: [(patterns: [Pattern], guard: Typed?, body: [Statement])])
    case `return`(Typed?)
    case `throw`(Typed)
    case `break`
    case `continue`
    case `defer`([Statement])
    case block([Statement])
    /// `do { … } catch { … }`: what the body throws is bound to `error`'s slot, and the first
    /// catch whose pattern matches runs.
    case doCatch(body: [Statement], error: Int, catches: [(pattern: Pattern?, body: [Statement])])
}

/// What an assignment writes.
package indirect enum Place {
    case local(Local)
    case global(String)
    /// A stored property of `self`, or of a value that's itself a place.
    case stored(Place?, index: Int)
    case subscripted(Place, by: [Typed], getter: StandardMember)
    case optional(Place)
}

package enum Condition {
    case boolean(Typed)
    /// `if let x = value`: the optional's value, bound when there is one.
    case bind(Int, Typed)
    case matches(Pattern, Typed)
}

package indirect enum Pattern {
    case wildcard
    case bind(Int)
    case value(Typed)
    case enumCase(String, [Pattern])
    case tuple([Pattern])
    case some(Pattern)
}

/// An expression and its type.
package struct Typed {
    package let expression: Expression
    package let type: SwiftType

    package init(_ expression: Expression, _ type: SwiftType) {
        self.expression = expression
        self.type = type
    }
}

/// A standard library member, as declared: `Array` and `append(_:)`, a property by its name, run
/// by the evaluator's own.
package struct StandardMember: Hashable {
    package let type: String
    package let member: String
}

package indirect enum Expression {
    case integer(Int)
    /// An integer literal of a fixed-width type, as its bits.
    case fixedInteger(FixedInteger, bits: UInt64)
    /// A `Range` or `ClosedRange` of values other than `Int`s, which read as the array of them.
    case range(Typed, Typed, closed: Bool)
    case double(Double)
    case string(String)
    /// A string literal of one character, where a `Character` is expected.
    case character(Character)
    case bool(Bool)
    case `nil`
    case interpolation([Piece])
    case local(Local)
    case selfValue
    case global(String)
    /// A type as a value: `Int.self`.
    case metatype(SwiftType)
    /// A stored property, by its index in its type.
    case stored(Typed, index: Int)
    /// A computed property's getter, on its value.
    case computed(Typed, ResolvedFunction)
    /// A method of the module's, on its value, or a global function when there's none.
    case call(ResolvedFunction, on: Typed?, [Argument])
    /// A standard library member, on its value, or static when there's none.
    case standard(StandardMember, on: Typed?, [Argument])
    /// A struct's or actor's initializer, or its memberwise one when there's none.
    case initialize(String, ResolvedFunction?, [Argument])
    case enumCase(String, String, [Typed])
    /// A message to another object: its method by name, with its arguments' labels.
    case message(to: Typed, String, labels: [String?], [Typed])
    /// A protocol's requirement called on a value of `any` of it: run as the value's own type
    /// meets it, or sent to it when it's another object.
    case witness(on: Typed, String, labels: [String?], [Typed])
    /// What another object publishes, read.
    case read(Typed, String)
    case array([Typed])
    case dictionary([(Typed, Typed)])
    case tuple([Typed])
    case element(Typed, Int)
    case closure(Closure)
    /// A closure value called.
    /// A function value called: its arguments, an `inout` one as the place it changes.
    case apply(Typed, [Argument])
    case unary(String, Typed)
    case binary(String, Typed, Typed)
    case and(Typed, Typed)
    case or(Typed, Typed)
    case ternary(Typed, Typed, Typed)
    case coalesce(Typed, Typed)
    case force(Typed)
    /// `base?.rest`: `rest` reads the base's value as `chained` when it has one, or is `nil`.
    case chain(Typed, Typed)
    case chained
    /// A value made optional.
    case wrap(Typed)
    /// A value as an existential: `any Sendable`, `Any`.
    case erase(Typed)
    case await(Typed)
    case `try`(Typed)
    case tryOptional(Typed)
    case tryForce(Typed)
    case cast(Typed, SwiftType, Cast)
    case assignment(Place, Typed)
    /// The raw value of an enum's case, or its case from one.
    case rawValue(Typed)
    case fromRawValue(String, Typed)
    /// A mutating method, on a value that's a place, which it writes back.
    case mutating(Place, Callee, [Argument])
}

/// What's called: a function of the module's, or the standard library's.
package enum Callee {
    case function(ResolvedFunction)
    case standard(StandardMember)
}

package enum Cast { case conditional, forced, check }

/// An argument, as the function takes it: given, or its parameter's default, or the values of a
/// variadic one.
package enum Argument {
    case value(Typed)
    case reference(Place)
    case variadic([Typed])
    case defaulted(Typed)
}

package enum Piece {
    case text(String)
    case value(Typed)
}

package final class Closure {
    package let parameters: Int
    package var body: [Statement] = []
    package var slots = 0

    init(parameters: Int) { self.parameters = parameters }
}
