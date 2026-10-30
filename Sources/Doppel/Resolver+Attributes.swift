import SwiftSyntax

extension Resolver {
    /// Each attribute of the checked file's declarations, as Swift checks it: a declaration
    /// modifier written as one is said to be one, one that names nothing declared is unknown, and
    /// a macro takes the arguments it's declared with and attaches where its roles let it.
    func checkAttributes() {
        final class Attributes: SyntaxVisitor {
            var found: [AttributeSyntax] = []

            override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
                found.append(node)
                return .skipChildren
            }

            /// A type's own attributes, a function type's `@Sendable`, are the type's: only a
            /// declaration modifier written as one is checked, `@actor Counter`.
            override func visit(_ node: AttributedTypeSyntax) -> SyntaxVisitorContinueKind {
                found += node.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter {
                    SwiftCheck.declarationModifiers.contains($0.attributeName.trimmedDescription)
                }
                return .skipChildren
            }
        }
        let attributes = Attributes(viewMode: .sourceAccurate)
        attributes.walk(checked)
        for attribute in attributes.found { check(attribute) }
    }

    private func check(_ attribute: AttributeSyntax) {
        let name = attribute.attributeName.trimmedDescription
        if SwiftCheck.declarationModifiers.contains(name) {
            report("'\(name)' is a declaration modifier, not an attribute", at: attribute)
            return
        }
        if let macro = module.macros[name] {
            if macro.parameters == 0, case .argumentList(let arguments)? = attribute.arguments,
                let first = arguments.first
            {
                report("argument passed to macro expansion that takes no arguments", at: first.expression)
            }
            if let declaration = attribute.parent?.parent?.as(DeclSyntax.self), let role = macro.roles.first,
                !macro.roles.contains(where: { Self.attaches($0, to: declaration) })
            {
                report("'\(role)' macro cannot be attached to \(Self.described(declaration))", at: attribute)
            }
            return
        }
        guard Self.builtInAttributes.contains(name) || module.attributeTypes.contains(name) else {
            report("unknown attribute '\(name)'", at: attribute.attributeName)
            return
        }
    }

    /// Whether a macro of `role` attaches to `declaration`, as Swift lets it.
    private static func attaches(_ role: String, to declaration: DeclSyntax) -> Bool {
        switch role {
        case "accessor":
            return declaration.is(VariableDeclSyntax.self) || declaration.is(SubscriptDeclSyntax.self)
        case "extension", "member", "memberAttribute", "conformance":
            return declaration.is(StructDeclSyntax.self) || declaration.is(EnumDeclSyntax.self)
                || declaration.is(ClassDeclSyntax.self) || declaration.is(ActorDeclSyntax.self)
                || declaration.is(ProtocolDeclSyntax.self)
                || (role != "extension" && declaration.is(ExtensionDeclSyntax.self))
        case "body", "preamble":
            return declaration.is(FunctionDeclSyntax.self) || declaration.is(InitializerDeclSyntax.self)
        default:
            return true
        }
    }

    /// A declaration as Swift says which one it is: `instance method ('add')`, `property ('count')`.
    private static func described(_ declaration: DeclSyntax) -> String {
        let inType = declaration.parent?.is(MemberBlockItemSyntax.self) == true
        let isStatic =
            declaration.asProtocol(WithModifiersSyntax.self)?.modifiers.contains {
                [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind)
            } == true
        if let function = declaration.as(FunctionDeclSyntax.self) {
            let kind = !inType ? "global function" : isStatic ? "static method" : "instance method"
            return "\(kind) ('\(function.name.text)')"
        }
        if let variable = declaration.as(VariableDeclSyntax.self) {
            let name = variable.bindings.first?.pattern.trimmedDescription ?? ""
            let kind = !inType ? "var" : isStatic ? "static property" : "property"
            return "\(kind) ('\(name)')"
        }
        if let structure = declaration.as(StructDeclSyntax.self) { return "struct ('\(structure.name.text)')" }
        if let enumeration = declaration.as(EnumDeclSyntax.self) { return "enum ('\(enumeration.name.text)')" }
        if let type = declaration.as(ClassDeclSyntax.self) { return "class ('\(type.name.text)')" }
        if let actor = declaration.as(ActorDeclSyntax.self) { return "actor ('\(actor.name.text)')" }
        if let type = declaration.as(ProtocolDeclSyntax.self) { return "protocol ('\(type.name.text)')" }
        if declaration.is(InitializerDeclSyntax.self) { return "initializer ('init')" }
        if declaration.is(ExtensionDeclSyntax.self) { return "extension" }
        return "declaration"
    }

    /// The attributes Swift has: those code is written with, and those it declares types and
    /// macros with.
    static let builtInAttributes: Set<String> = [
        "attached", "autoclosure", "available", "backDeployed", "discardableResult", "dynamicCallable",
        "dynamicMemberLookup", "escaping", "freestanding", "frozen", "globalActor", "IBAction", "IBDesignable",
        "IBInspectable", "IBOutlet", "IBSegueAction", "inlinable", "inline", "main", "MainActor", "NSCopying",
        "NSManaged", "nonobjc", "objc", "objcMembers", "preconcurrency", "propertyWrapper",
        "requires_stored_property_inits",
        "resultBuilder", "retroactive", "Sendable", "TaskLocal", "testable", "unchecked", "unknown",
        "usableFromInline", "warn_unqualified_access",
    ]
}

extension SwiftCheck {
    /// The keywords that modify a declaration, which Swift says aren't attributes when one's
    /// written as one: `@actor` is `actor`.
    public static let declarationModifiers: Set<String> = [
        "actor", "class", "convenience", "distributed", "dynamic", "fileprivate", "final", "indirect", "internal",
        "lazy", "mutating", "nonisolated", "nonmutating", "open", "optional", "override", "private", "public",
        "required", "static", "unowned", "weak",
    ]
}
