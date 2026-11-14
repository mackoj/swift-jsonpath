import LLMCheck
import Testing

/// Each detector on snippets: it finds what its rule forbids and nothing its rule allows.
@Suite struct DetectorTests {
    func scope(_ source: String, at path: String = "Sources/JSONPath/File.swift") -> Scope {
        Scope(files: [SourceFile(path: path, source: source)])
    }

    @Test func importsAreFound() {
        let found = Detect.imports(
            in: scope(
                """
                import Foundation
                #if canImport(Glibc)
                import Glibc
                #endif
                @_exported import struct Swift.Int
                """))
        #expect(found.map(\.location.line) == [1, 3, 5])
    }

    @Test func noImportsPass() {
        let found = Detect.imports(in: scope("// import Foundation\nlet text = \"import Foundation\""))
        #expect(found.isEmpty)
    }

    @Test func impureCodeIsFound() {
        let found = Detect.impureCode(
            in: scope(
                """
                print("parsed")
                debugPrint(path)
                let line = readLine()
                let arguments = CommandLine.arguments
                let index = Int.random(in: 0..<3)
                let order = values.shuffled()
                var generator = SystemRandomNumberGenerator()
                """))
        #expect(found.map(\.location.line).sorted() == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func pureCodePasses() {
        let found = Detect.impureCode(
            in: scope(
                """
                // print() and CommandLine are fine in a comment.
                let message = "print(x) and Int.random() are fine in a string"
                printer.print(value)
                let access = randomAccess(values)
                func dump(into output: inout String) {}
                """))
        #expect(found.isEmpty)
    }

    @Test func publicReferenceTypesAreFound() {
        let found = Detect.publicReferenceTypes(
            in: scope(
                """
                public final class Pointer {}
                open class Base {}
                public actor Cache {}
                final class ObjectStorage {}
                public struct Value {}
                """))
        #expect(found.map(\.name) == ["Pointer", "Base", "Cache"])
    }

    @Test func missingConformancesAreFound() {
        let found = Detect.publicTypesMissingConformances(
            in: scope(
                """
                public struct NormalizedPath: CustomStringConvertible {
                    public enum Element: Hashable { case name(String) }
                }
                public struct JSONPointer: Hashable, Sendable {}
                public struct Options: Sendable {}
                struct Internal {}
                """))
        #expect(found.map(\.qualifiedName) == ["NormalizedPath", "Options", "NormalizedPath.Element"])
    }

    @Test func conformancesInExtensionsCount() {
        let found = Detect.publicTypesMissingConformances(
            in: scope(
                """
                public struct OrderedDictionary<Key: Hashable, Value> {}
                extension OrderedDictionary: Hashable where Value: Hashable {}
                extension OrderedDictionary: Sendable where Key: Sendable, Value: Sendable {}
                public struct Pair<Value> {}
                extension Pair: Hashable where Value: Hashable {}
                """))
        #expect(found.map(\.name) == ["Pair"])
    }

    @Test func listedCodersNeedOnlySendable() {
        let found = Detect.publicTypesMissingConformances(
            in: scope(
                """
                public struct JSONValueDecoder: Sendable {}
                public struct JSONValueEncoder {}
                """))
        #expect(found.map(\.name) == ["JSONValueEncoder"])
    }

    @Test func todoStubsAreFound() {
        let found = Detect.todoStubs(
            in: scope(
                """
                fatalError("TODO: Jayway slices")
                fatalError("todo")
                preconditionFailure("Unimplemented")
                fatalError("not implemented yet")
                """))
        #expect(found.map(\.location.line) == [1, 2, 3, 4])
    }

    @Test func realFailuresPass() {
        let found = Detect.todoStubs(
            in: scope(
                """
                fatalError("unreachable: the parser rejects empty selectors")
                preconditionFailure(message)
                fatalError()
                """))
        #expect(found.isEmpty)
    }
}
