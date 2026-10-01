//
//  AQLCollectionServicesTests.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

@MainActor
@Suite("AQL Collection services")
struct AQLCollectionServicesTests {
    nonisolated static let abc = seq("a", "b", "c")

    nonisolated static let cases: [LibraryCase] = [
        LibraryCase(abc, "size", expect: 3),
        LibraryCase(seq(), "isEmpty", expect: true),
        LibraryCase(abc, "notEmpty", expect: true),
        LibraryCase(abc, "first", expect: "a"),
        LibraryCase(abc, "last", expect: "c"),
        LibraryCase(seq(), "first", expect: nil),
        LibraryCase(abc, "at", 1, expect: "a"),
        LibraryCase(abc, "at", 2, expect: "b"),
        LibraryCase(abc, "at", 0, expect: nil),
        LibraryCase(abc, "at", 4, expect: nil),
        LibraryCase(abc, "indexOf", "b", expect: 2),
        LibraryCase(abc, "indexOf", "z", expect: 0),
        LibraryCase(seq(1, 2, 3, 4, 3), "lastIndexOf", 3, expect: 5),
        LibraryCase(abc, "includes", "a", expect: true),
        LibraryCase(abc, "includes", "z", expect: false),
        LibraryCase(abc, "contains", "c", expect: true),
        LibraryCase(abc, "excludes", "z", expect: true),
        LibraryCase(abc, "includesAll", seq("a"), expect: true),
        LibraryCase(abc, "includesAll", seq("a", "f"), expect: false),
        LibraryCase(seq("a", "b"), "excludesAll", seq("f"), expect: true),
        LibraryCase(seq("a", "b"), "excludesAll", seq("a", "f"), expect: false),
        LibraryCase(abc, "including", "d", expect: seq("a", "b", "c", "d")),
        LibraryCase(abc, "excluding", "c", expect: seq("a", "b")),
        LibraryCase(seq("a", "b", "a"), "excluding", "a", expect: seq("b")),
        LibraryCase(abc, "union", seq("d", "c"), expect: seq("a", "b", "c", "d")),
        LibraryCase(abc, "intersection", seq("a", "f"), expect: seq("a")),
        LibraryCase(abc, "sub", seq("a"), expect: seq("b", "c")),
        LibraryCase(abc, "difference", seq("b"), expect: seq("a", "c")),
        LibraryCase(abc, "concat", seq("d", "e"), expect: seq("a", "b", "c", "d", "e")),
        LibraryCase(abc, "append", "f", expect: seq("a", "b", "c", "f")),
        LibraryCase(abc, "prepend", "f", expect: seq("f", "a", "b", "c")),
        LibraryCase(abc, "insertAt", 2, "f", expect: seq("a", "f", "b", "c")),
        LibraryCase(abc, "insertAt", 9, "f", expect: nil),
        LibraryCase(abc, "reverse", expect: seq("c", "b", "a")),
        LibraryCase(seq(seq(1, 2), seq(seq(3)), 4), "flatten", expect: seq(1, 2, 3, 4)),
        LibraryCase(seq("a", "b", "c", "c", "a"), "asSet", expect: abc),
        LibraryCase(seq("a", "a"), "asOrderedSet", expect: seq("a")),
        LibraryCase(abc, "asSequence", expect: abc),
        LibraryCase(abc, "asBag", expect: abc),
        LibraryCase(seq(1, 2, 3, 4), "sum", expect: 10),
        LibraryCase(seq(1, 2.5), "sum", expect: 3.5),
        LibraryCase(seq(), "sum", expect: 0),
        LibraryCase(seq("a", "b"), "sum", expect: "ab"),
        LibraryCase(seq(1, 2, 3.14, 4), "min", expect: 1.0),
        LibraryCase(seq(1, 2, 3, 4), "min", expect: 1),
        LibraryCase(seq(1, 2, 3.14, 4), "max", expect: 4.0),
        LibraryCase(seq(1, 2, 3, 4), "max", expect: 4),
        LibraryCase(abc, "count", "a", expect: 1),
        LibraryCase(abc, "count", "d", expect: 0),
        LibraryCase(abc, "drop", 2, expect: seq("c")),
        LibraryCase(abc, "dropRight", 2, expect: seq("a")),
        LibraryCase(abc, "subSequence", 1, 2, expect: seq("a", "b")),
        LibraryCase(abc, "subOrderedSet", 2, 3, expect: seq("b", "c")),
        LibraryCase(abc, "subSequence", 2, 9, expect: nil),
        LibraryCase(abc, "sep", "-", expect: seq("a", "-", "b", "-", "c")),
        LibraryCase(abc, "sep", "[", "-", "]", expect: seq("[", "a", "-", "b", "-", "c", "]")),
        LibraryCase(seq(), "sep", "[", "-", "]", expect: seq("[", "]")),
        LibraryCase(seq(), "sep", "[", "-", "]", false, expect: seq()),
        LibraryCase(seq("a", 1, 3.14), "filter", AQLTypeDescriptor(typeName: "String"), expect: seq("a")),
        LibraryCase(seq("a", 1, 3.14), "filter", AQLTypeDescriptor(typeName: "Integer"), expect: seq(1)),
        LibraryCase(seq("a", 1, 3.14), "filter", AQLTypeDescriptor(typeName: "Real"), expect: seq(3.14)),
        LibraryCase("x", "size", expect: 1, arrow: true),
        LibraryCase(nil, "size", expect: 0, arrow: true),
        LibraryCase(nil, "isEmpty", expect: true, arrow: true),
        LibraryCase(abc, "toString", expect: "[a, b, c]"),
    ]

    @Test("Collection library behaviour", arguments: cases)
    func library(_ test: LibraryCase) async throws {
        try await check(test)
    }

    @Test("Both call forms reach the same implementation", arguments: ["size", "first", "reverse", "asSet"])
    func dotAndArrow(_ name: String) async throws {
        let dot = try await evaluate(LibraryCase(Self.abc, name, expect: nil))
        let arrow = try await evaluate(LibraryCase(Self.abc, name, expect: nil, arrow: true))
        #expect(AQLValues.areEqual(dot, arrow))
    }

    @Test("Native arrays are accepted as collections")
    func nativeArrays() async throws {
        let result = try await evaluate(LibraryCase(["x", "y"], "size", expect: nil))
        #expect(result as? Int == 2)
    }

    // MARK: Iterators

    private func lambda(_ body: any AQLExpression) -> AQLLambdaExpression {
        AQLLambdaExpression(iterator: "x", body: body)
    }

    private func call(_ method: String, on items: EcoreValueArray, _ argument: any AQLExpression) async throws
        -> (any EcoreValue)?
    {
        try await AQLCallExpression(
            source: lit(items), methodName: method, arguments: [argument], usesArrow: true
        ).evaluate(in: makeContext())
    }

    private var numbers: EcoreValueArray { seq(1, 2, 3, 4) }

    private var isEven: AQLLambdaExpression {
        lambda(
            AQLBinaryExpression(
                left: AQLBinaryExpression(left: AQLVariableExpression(name: "x"), op: .mod, right: lit(2)),
                op: .equals, right: lit(0)))
    }

    @Test func select() async throws {
        #expect(AQLValues.areEqual(try await call("select", on: numbers, isEven), seq(2, 4)))
    }

    @Test func reject() async throws {
        #expect(AQLValues.areEqual(try await call("reject", on: numbers, isEven), seq(1, 3)))
    }

    @Test func collect() async throws {
        let double = lambda(AQLBinaryExpression(left: AQLVariableExpression(name: "x"), op: .multiply, right: lit(2)))
        #expect(AQLValues.areEqual(try await call("collect", on: numbers, double), seq(2, 4, 6, 8)))
    }

    @Test func collectFlattensCollections() async throws {
        let pair = lambda(AQLCollectionLiteralExpression(kind: .sequence, elements: [AQLVariableExpression(name: "x"), lit(0)]))
        #expect(AQLValues.areEqual(try await call("collect", on: seq(1, 2), pair), seq(1, 0, 2, 0)))
    }

    @Test func anyReturnsElement() async throws {
        #expect(try await call("any", on: numbers, isEven) as? Int == 2)
        let none = lambda(lit(false))
        #expect(try await call("any", on: numbers, none) == nil)
    }

    @Test func existsForAllOne() async throws {
        #expect(try await call("exists", on: numbers, isEven) as? Bool == true)
        #expect(try await call("forAll", on: numbers, isEven) as? Bool == false)
        #expect(try await call("forAll", on: seq(2, 4), isEven) as? Bool == true)
        #expect(try await call("one", on: seq(1, 2, 3), isEven) as? Bool == true)
        #expect(try await call("one", on: numbers, isEven) as? Bool == false)
    }

    @Test func isUnique() async throws {
        let size = lambda(AQLCallExpression(source: AQLVariableExpression(name: "x"), methodName: "size"))
        #expect(try await call("isUnique", on: seq("a", "bb", "ccc"), size) as? Bool == true)
        #expect(try await call("isUnique", on: seq("a", "b"), size) as? Bool == false)
    }

    @Test func sortedBy() async throws {
        let size = lambda(AQLCallExpression(source: AQLVariableExpression(name: "x"), methodName: "size"))
        let result = try await call("sortedBy", on: seq("aa", "bbb", "c", "dd"), size)
        #expect(AQLValues.areEqual(result, seq("c", "aa", "dd", "bbb")))
    }

    @Test func closureExcludesSourceAndTerminates() async throws {
        let context = makeContext()
        context.setVariable("next", value: EcoreValueArray([]))
        // x -> x + 1 while x < 4, else null: closure of {1} is {2, 3, 4}
        let step = lambda(
            AQLConditionalExpression(
                condition: AQLBinaryExpression(left: AQLVariableExpression(name: "x"), op: .lessThan, right: lit(4)),
                thenExpression: AQLBinaryExpression(left: AQLVariableExpression(name: "x"), op: .add, right: lit(1)),
                elseExpression: lit(nil)))
        let result = try await call("closure", on: seq(1), step)
        #expect(AQLValues.areEqual(result, seq(2, 3, 4)))
    }

    @Test func indexOfWithLambda() async throws {
        #expect(try await call("indexOf", on: numbers, isEven) as? Int == 2)
    }

    @Test func oneBasedIndexOf() async throws {
        let context = makeContext()
        context.usesOneBasedIndexOf = true
        let found = try await evaluate(LibraryCase(seq(1, 2, 3, 4), "indexOf", 3, expect: nil), in: context)
        let absent = try await evaluate(LibraryCase(seq(1, 2), "indexOf", 9, expect: nil), in: context)
        #expect(found as? Int == 3)
        #expect(absent as? Int == 0)
    }

    @Test func indexOfIsOneBasedByDefault() async throws {
        let context = makeContext()
        #expect(context.usesOneBasedIndexOf)
        let found = try await evaluate(LibraryCase(seq(1, 2, 3, 4), "indexOf", 3, expect: nil), in: context)
        let absent = try await evaluate(LibraryCase(seq(1, 2), "indexOf", 9, expect: nil), in: context)
        let last = try await evaluate(LibraryCase(seq(1, 2, 1), "lastIndexOf", 1, expect: nil), in: context)
        #expect(found as? Int == 3)
        #expect(absent as? Int == 0)
        #expect(last as? Int == 3)
    }

    @Test func zeroBasedIndexOfRemainsAvailable() async throws {
        let context = makeContext()
        context.usesOneBasedIndexOf = false
        let found = try await evaluate(LibraryCase(seq(1, 2, 3, 4), "indexOf", 3, expect: nil), in: context)
        let absent = try await evaluate(LibraryCase(seq(1, 2), "indexOf", 9, expect: nil), in: context)
        #expect(found as? Int == 2)
        #expect(absent as? Int == -1)
    }

    @Test func collectionExpressionDelegates() async throws {
        let expr = AQLCollectionExpression(
            source: lit(numbers), operation: .select, iterator: "x", body: isEven.body)
        #expect(AQLValues.areEqual(try await expr.evaluate(in: makeContext()), seq(2, 4)))
        let sorted = AQLCollectionExpression(
            source: lit(seq(3, 1, 2)), operation: .sortedBy, iterator: "x",
            body: AQLVariableExpression(name: "x"))
        #expect(AQLValues.areEqual(try await sorted.evaluate(in: makeContext()), seq(1, 2, 3)))
        let nothing = AQLCollectionExpression(source: lit(nil), operation: .select, iterator: "x", body: lit(true))
        #expect(try await nothing.evaluate(in: makeContext()) == nil)
    }

    // MARK: Equality

    @Test("Objects compare by identity, values by value")
    func equality() async throws {
        let eClass = EClass(name: "Thing")
        let a = DynamicEObject(eClass: eClass)
        let b = DynamicEObject(eClass: eClass)
        let items = seq(a, "x", 1)
        #expect(try await evaluate(LibraryCase(items, "includes", a, expect: nil)) as? Bool == true)
        #expect(try await evaluate(LibraryCase(items, "includes", b, expect: nil)) as? Bool == false)
        #expect(try await evaluate(LibraryCase(items, "includes", 1.0, expect: nil)) as? Bool == true)
        #expect(try await evaluate(LibraryCase(items, "includes", "1", expect: nil)) as? Bool == false)
        #expect(try await evaluate(LibraryCase(seq(a, b, a), "asSet", expect: nil)).flatMap { AQLValues.elements(of: $0) }?.count == 2)
    }
}
