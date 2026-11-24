package import SwiftSyntax

/// What the runtime reads of a type's declaration.
extension TypeDeclaration {
    package var storedNames: [String] { stored.map(\.name) }
    package var caseNames: [String] { cases.map(\.name) }
    package func caseValues(_ name: String) -> [Parameter] { self.case(name)?.values ?? [] }
    package func method(_ name: String) -> [Function] { methods[name] ?? [] }
    package var isActor: Bool { kind == .actor }
    package var isEnum: Bool { kind == .enumeration }
    package var isStruct: Bool { kind == .structure }
}

/// An enum case's raw value, as Swift gives it: written, or the case's name for a `String` enum,
/// or one more than the case before for an `Int` one.
package enum RawValue {
    case int(Int)
    case double(Double)
    case string(String)
}

extension ResolvedProgram {
    package func storedType(of type: TypeDeclaration, at index: Int) -> SwiftType {
        resolver.propertyType(type.stored[index], of: type)
    }

    package func type(of property: Property, in type: TypeDeclaration) -> SwiftType {
        resolver.propertyType(property, of: type)
    }

    package func rawValue(of type: TypeDeclaration, case name: String) -> RawValue? {
        guard let raw = type.rawType else { return nil }
        var next = 0
        for enumCase in type.cases {
            let text = enumCase.rawValue?.trimmedDescription
            let value: RawValue
            switch raw {
            case .string: value = .string(text.map { String($0.dropFirst().dropLast()) } ?? enumCase.name)
            case .int:
                let number = text.flatMap { Int($0) } ?? next
                next = number + 1
                value = .int(number)
            case .double: value = .double(text.flatMap { Double($0) } ?? Double(next))
            default: return nil
            }
            if enumCase.name == name { return value }
        }
        return nil
    }
}

extension TypeDeclaration {
    package var declarationSyntax: Syntax? { syntax.map(Syntax.init) }
    package func storedProperty(_ index: Int) -> Property { stored[index] }
    /// The stored properties a memberwise initializer takes, by index, in order: those that may
    /// change or have no value.
    package var memberwiseFields: [Int] { stored.indices.filter { stored[$0].mutable || !stored[$0].hasValue } }
}
