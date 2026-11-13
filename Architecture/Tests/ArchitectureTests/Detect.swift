import LLMCheck
import SwiftSyntax

/// The detectors, separate from the codebase so `DetectorTests` can run them on snippets.
enum Detect {
    /// Every `import`, in `#if` blocks too: `Sources` imports nothing.
    static func imports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
        scope.imports
    }

    /// Free functions that write to standard output or read standard input.
    static let consoleFunctions: Set<String> = ["print", "debugPrint", "dump", "readLine"]

    /// Methods whose result depends on a random number generator.
    static let randomMethods: Set<String> = ["random", "randomElement", "shuffled", "shuffle"]

    /// Types whose every use reads the process's input or a random source.
    static let impureTypes: Set<String> = ["CommandLine", "SystemRandomNumberGenerator"]

    /// `print(x)`, `readLine()`, `Int.random(in:)`, `values.shuffled()`, `CommandLine.arguments`.
    /// `printer.print(x)` and `randomAccess(…)` pass.
    static func impureCode(in scope: Scope) -> [Match<Syntax>] {
        let console = scope.calls(named: consoleFunctions).filter {
            $0.node.calledExpression.is(DeclReferenceExprSyntax.self)
        }
        let random = scope.calls(named: randomMethods).filter {
            $0.node.calledExpression.is(MemberAccessExprSyntax.self)
        }
        return scope.references(to: impureTypes)
            + (console + random).map { Match(node: Syntax($0.node), file: $0.file) }
    }

    /// Public or open classes and public actors.
    static func publicReferenceTypes(in scope: Scope) -> [Declaration] {
        (scope.classes + scope.actors).filter { $0.hasModifier("public") || $0.hasModifier("open") }
    }

    /// Public types that cannot be `Hashable`: their stored properties hold `any Sendable`.
    static let notHashable: Set<String> = ["JSONValueDecoder", "JSONValueEncoder"]

    /// Public structs and enums not declared `Sendable`, or not `Hashable` unless listed in ``notHashable``. A
    /// conformance counts on the type or on an extension of it, where a generic type declares a conditional one.
    static func publicTypesMissingConformances(in scope: Scope) -> [Declaration] {
        let extensions = scope.extensions
        return (scope.structs + scope.enums).withModifier("public").filter { type in
            let declarations = [type] + extensions.filter { $0.name == type.qualifiedName }
            func conforms(to name: String) -> Bool { declarations.contains { $0.inherits(from: name) } }
            return !conforms(to: "Sendable") || !(conforms(to: "Hashable") || notHashable.contains(type.qualifiedName))
        }
    }

    /// `@unchecked Sendable` conformances with no comment on the declaration that makes them.
    static func uncommentedUncheckedSendable(in scope: Scope) -> [Match<AttributeSyntax>] {
        scope.containing("@unchecked").nodes(of: AttributeSyntax.self) { match in
            guard match.node.attributeName.trimmedDescription == "unchecked" else { return false }
            let declaration = sequence(first: Syntax(match.node), next: \.parent).first { $0.is(DeclSyntax.self) }
            return declaration?.attachedComments.isEmpty ?? true
        }
    }

    /// `fatalError("TODO …")`, `preconditionFailure("unimplemented")` and the like: a stub that compiles.
    static func todoStubs(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
        scope.calls(named: "fatalError", "preconditionFailure").filter { call in
            guard let message = call.node.arguments.first?.expression.as(StringLiteralExprSyntax.self) else {
                return false
            }
            let text = message.segments.trimmedDescription.lowercased()
            return ["todo", "fixme", "unimplemented", "not implemented", "not yet implemented"].contains {
                text.hasPrefix($0)
            }
        }
    }

    /// `import XCTest`.
    static func xcTestImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
        scope.imports(of: "XCTest")
    }

    /// `withKnownIssue { … }` whose first argument is not a string literal: the reason.
    static func unexplainedKnownIssues(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
        scope.calls(named: "withKnownIssue").filter { call in
            guard let first = call.node.arguments.first, first.label == nil else { return true }
            return !first.expression.is(StringLiteralExprSyntax.self)
        }
    }

    /// The `.disabled(…)` trait, wherever a test or suite takes it.
    static func disabledTests(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
        scope.calls(named: "disabled").filter { call in
            call.node.receiver == nil && call.node.calledExpression.is(MemberAccessExprSyntax.self)
        }
    }
}
