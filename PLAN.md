# Doppel plan

## The standard library from Swift's own

Swift has 94 public protocols in its standard library. Copying them by hand into
`StandardLibrary.swift` never ends and drifts from Swift. Instead, generate them
from Swift's own interface, `Swift.swiftinterface` in the SDK: the file the
compiler reads. The generator is a dev tool. Nothing it needs ships, so checking
and running stay on the device.

What Swift says stays the source. When Swift changes a protocol, regenerate.
Every step is checked against `swiftc` by the agreement harness and the runtime
programs.

### Steps

1. **Generator.** Read the protocols and their requirements from the interface
   and strip what's the compiler's own: `Swift::` prefixes, `__owned`,
   `__consuming`, `@_` attributes, `#if` compiler checks. Replace the
   hand-written `Identifiable`, `RawRepresentable`, `CaseIterable`, `OptionSet`
   and `Strideable` with the generated ones. About ½ day.
2. **Conformance, as Swift checks it.** Most of the work is here. A type must
   meet a protocol's requirements. Associated types are inferred from what meets
   them (`var id: Int` makes `ID` an `Int`), including defaults
   (`AllCases = [Self]`), primary associated types (`Identifiable<ID>`) and
   `where` on associated types. Go only as far as object code needs. About
   1½–2 days.
3. **Conformances Swift gives for free.** A raw-value enum is `RawRepresentable`,
   and a case-only enum gets `allCases`. The `Equatable` and `Hashable` ones move
   onto the same footing. About ½ day.
4. **Literal protocols, once object code needs them.** `ExpressibleByIntegerLiteral`,
   `…StringLiteral`, `…ArrayLiteral` and the rest: a literal is typed by what
   it's used as, not fixed. This touches every literal, so the agreement corpus
   has to hold. About 1 day.
5. **Default implementations**, taken per protocol as code needs them, from the
   interface's `@inlinable` bodies. What's built on `Builtin.` or unsafe
   pointers becomes a native member, as `String`'s and `Array`'s cores are now.
   Ongoing, in small steps.

### Measured in the interface (Swift 6.4, macOS 27 SDK)

59,328 lines; 94 public protocols, 15 with primary associated types; 2,125
extensions, 682 with `where`; 2,911 `@inlinable` bodies; 3,018 uses of
`Builtin.`, 1,430 of unsafe pointers, 406 of `~Copyable`/`~Escapable`, 214 of
typed throws.

### Done before this plan (2026-10-20)

`Optional` is the standard library's enum, and `ExpressibleByNilLiteral` exists.
`Result` is written in Swift. Generic enums now work: cases carry their type's
arguments, patterns see the real value types, and the type's constraints apply
in its members. Switch exhaustiveness is checked over the pattern's structure.
Enums can assign to `self` in initializers and mutating methods. Nested types
are named `Outer.Inner`. A value that isn't of its type is refused with its path.
