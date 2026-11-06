//
//  AQLNumberServicesTests.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Testing

@testable import AQL

@MainActor
@Suite("AQL Number and Boolean services")
struct AQLNumberServicesTests {
    nonisolated static let cases: [LibraryCase] = [
        LibraryCase(-3, "abs", expect: 3),
        LibraryCase(-2.5, "abs", expect: 2.5),
        LibraryCase(3, "min", 5, expect: 3),
        LibraryCase(3, "max", 5, expect: 5),
        LibraryCase(3, "max", 5.5, expect: 5.5),
        LibraryCase(2.5, "min", 7, expect: 2.5),
        LibraryCase(2.5, "floor", expect: 2),
        LibraryCase(2.5, "ceil", expect: 3),
        LibraryCase(2.5, "round", expect: 3),
        LibraryCase(7, "div", 2, expect: 3),
        LibraryCase(7, "mod", 4, expect: 3),
        LibraryCase(true, "not", expect: false),
        LibraryCase(true, "and", false, expect: false),
        LibraryCase(false, "or", true, expect: true),
        LibraryCase(true, "xor", true, expect: false),
        LibraryCase(true, "implies", false, expect: false),
        LibraryCase(false, "implies", false, expect: true),
        LibraryCase(1, "toString", expect: "1"),
        LibraryCase(1.0, "toString", expect: "1.0"),
        LibraryCase(true, "toString", expect: "true"),
        LibraryCase(nil, "toString", expect: "null"),
    ]

    @Test("Number and boolean library behaviour", arguments: cases)
    func library(_ test: LibraryCase) async throws {
        try await check(test)
    }

    /// Additions with the `add` service of numbers, which yields what `+` yields.
    nonisolated static let additions: [KindExample] = [
        KindExample("1.add(2)", "3"),
        KindExample("1.add(2)", "1 + 2"),
        KindExample("1.5.add(2)", "3.5"),
        KindExample("2.add(0.5)", "2.5"),
        KindExample("1.add('x')", "'1x'"),
        KindExample("Sequence{1}.add(2)", "Sequence{3}"),
        KindExample("Sequence{1, 2.5}.add(1)", "Sequence{2, 3.5}"),
        KindExample("OrderedSet{1, 2}.add(-1)", "OrderedSet{0, 1}"),
    ]

    @Test("Numbers add as + does", arguments: additions)
    func addition(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    @Test("Numbers add under the legacy options")
    func legacyAddition() async throws {
        let context = makeContext(options: .legacy)
        #expect(try await AQLCollectionKindTests.value(of: "1.add(2)", in: context) as? Int == 3)
        #expect(try await AQLCollectionKindTests.value(of: "1.5.add(2)", in: context) as? Double == 3.5)
    }

    @Test("Adding a collection to a number fails as + does", arguments: ["1.add(Sequence{2})", "1 + Sequence{2}"])
    func invalidAddition(_ source: String) async throws {
        await #expect(throws: AQLExecutionError.self) { _ = try await AQLCollectionKindTests.value(of: source) }
    }

    @Test("Division by zero is reported")
    func divisionByZero() async throws {
        await #expect(throws: AQLExecutionError.self) {
            _ = try await evaluate(LibraryCase(1, "div", 0, expect: nil))
        }
    }

    @Test("Standalone min and max keep working")
    func standalone() async throws {
        let context = makeContext()
        let minimum = try await AQLCallExpression(methodName: "min", arguments: [lit(4), lit(2)]).evaluate(in: context)
        let maximum = try await AQLCallExpression(methodName: "max", arguments: [lit(4.5), lit(2.0)]).evaluate(in: context)
        let absolute = try await AQLCallExpression(methodName: "abs", arguments: [lit(-4)]).evaluate(in: context)
        #expect(minimum as? Int == 2)
        #expect(maximum as? Double == 4.5)
        #expect(absolute as? Int == 4)
    }

    @Test("Binary operators: div, mod, xor, implies, real and null literals")
    func binaryOperators() async throws {
        let context = makeContext()
        func run(_ op: AQLBinaryExpression.Operator, _ l: any EcoreValue, _ r: any EcoreValue) async throws -> (any EcoreValue)? {
            try await AQLBinaryExpression(left: lit(l), op: op, right: lit(r)).evaluate(in: context)
        }
        #expect(try await run(.div, 7, 2) as? Int == 3)
        #expect(try await run(.mod, 7, 4) as? Int == 3)
        #expect(try await run(.xor, true, false) as? Bool == true)
        #expect(try await run(.implies, true, false) as? Bool == false)
        #expect(try await run(.add, 1.5, 2.25) as? Double == 3.75)
        #expect(try await run(.add, "a", "b") as? String == "ab")
        #expect(try await run(.equals, 1, 1.0) as? Bool == true)
        #expect(try await run(.equals, "1", 1) as? Bool == false)
        #expect(try await AQLLiteralExpression(value: nil).evaluate(in: context) == nil)
        await #expect(throws: AQLExecutionError.self) { _ = try await run(.div, 1.5, 2) }
        await #expect(throws: AQLExecutionError.self) { _ = try await run(.div, 1, 0) }
    }
}
