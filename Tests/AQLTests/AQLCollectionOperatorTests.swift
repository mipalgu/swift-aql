//
//  AQLCollectionOperatorTests.swift
//  AQL
//
//  Created by Rene Hexel on 5/11/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

@MainActor
@Suite("AQL Collection operators")
struct AQLCollectionOperatorTests {

    // MARK: Addition

    /// `+` and `add` between two collections.
    nonisolated static let additions: [KindExample] = [
        KindExample("Sequence{'a', 'b', 'c'} + Sequence{'d', 'e'}", "Sequence{'a', 'b', 'c', 'd', 'e'}"),
        KindExample("Sequence{'a', 'b', 'c'}.add(Sequence{'d', 'e'})", "Sequence{'a', 'b', 'c', 'd', 'e'}"),
        KindExample("Sequence{'a', 'b', 'c'}->add(Sequence{'d', 'e'})", "Sequence{'a', 'b', 'c', 'd', 'e'}"),
        KindExample("Sequence{'a', 'b', 'c'} + OrderedSet{'c', 'e'}", "Sequence{'a', 'b', 'c', 'c', 'e'}"),
        KindExample("Sequence{'a', 'b'} + Sequence{'b', 'a'}", "Sequence{'a', 'b', 'b', 'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'} + OrderedSet{'c', 'b', 'f'}", "OrderedSet{'a', 'b', 'c', 'f'}"),
        KindExample("OrderedSet{'a', 'b'} + Sequence{'b', 'c', 'c'}", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b'}->add(Sequence{'b', 'c'})", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("Set{'a', 'b'} + Set{'b', 'c'}", "Set{'a', 'b', 'c'}"),
        KindExample("Bag{'a', 'b'} + Sequence{'b'}", "Bag{'a', 'b', 'b'}"),
        KindExample("Sequence{} + Sequence{}", "Sequence{}"),
        KindExample("Sequence{'a'} + Sequence{} + Sequence{'a'}", "Sequence{'a', 'a'}"),
        KindExample("'hello'->add(Sequence{1, 2, 3})", "Set{'hello', 1, 2, 3}"),
        KindExample("(Sequence{1, 2} + Sequence{3})->size()", "3"),
    ]

    @Test("Adding collections concatenates them in the kind of the left operand", arguments: additions)
    func addition(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    /// `+` and `add` between a string and another value.
    nonisolated static let textAdditions: [KindExample] = [
        KindExample("'a' + 'b'", "'ab'"),
        KindExample("'x' + Sequence{'a', 'b'}", "'xab'"),
        KindExample("Sequence{'a', 'b'} + 'x'", "'abx'"),
        KindExample("OrderedSet{'a', 'b'} + 'x'", "'abx'"),
        KindExample("'x' + Sequence{Sequence{'a'}, 'b', 1}", "'xab1'"),
        KindExample("'x' + Sequence{}", "'x'"),
        KindExample("'times ' + 42", "'times 42'"),
        KindExample("42 + ' times'", "'42 times'"),
        KindExample("'is ' + true", "'is true'"),
        KindExample("Sequence{'a'}.add('b')", "'ab'"),
        KindExample("'a'.add(Sequence{'b', 'c'})", "'abc'"),
        KindExample("'a'.add('b')", "'ab'"),
        KindExample("'a'.add(1)", "'a1'"),
    ]

    @Test("Adding a string to any value concatenates their text", arguments: textAdditions)
    func textAddition(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    @Test(
        "Adding a collection and a value that is neither a collection nor a string fails",
        arguments: ["Sequence{1} + 2", "1 + Sequence{2}", "Sequence{1}.add(2)", "OrderedSet{1}->add(2)", "true + Sequence{}"])
    func invalidAddition(_ source: String) async throws {
        await #expect(throws: AQLExecutionError.self) { _ = try await AQLCollectionKindTests.value(of: source) }
    }

    /// `+` and `add` with a null operand, which counts as empty text.
    nonisolated static let nullAdditions: [KindExample] = [
        KindExample("'x' + null", "'x'"),
        KindExample("null + 'x'", "'x'"),
        KindExample("null + null", "''"),
        KindExample("Sequence{'a', 'b'} + null", "'ab'"),
        KindExample("null + Sequence{'a', 'b'}", "'ab'"),
        KindExample("OrderedSet{Sequence{'a'}, 'b'} + null", "'ab'"),
        KindExample("null + 1", "'1'"),
        KindExample("2.5 + null", "'2.5'"),
        KindExample("null + false", "'false'"),
        KindExample("Sequence{'a'}.add(null)", "'a'"),
        KindExample("Sequence{'a'}->add(null)", "'a'"),
        KindExample("'a'.add(null)", "'a'"),
        KindExample("null->add('x')", "'x'"),
    ]

    @Test("Adding null treats it as empty text", arguments: nullAdditions)
    func nullAddition(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    @Test("Subtracting null still yields null", arguments: ["Sequence{'a'} - null", "null - Sequence{'a'}", "null - 1"])
    func nullSubtraction(_ source: String) async throws {
        #expect(try await AQLCollectionKindTests.value(of: source) == nil)
    }

    // MARK: Text

    /// `toString` of collections and null, and the text that `+` joins.
    nonisolated static let texts: [KindExample] = [
        KindExample("Sequence{'a', 'b'}->toString()", "'ab'"),
        KindExample("Sequence{'a', 'b'}.toString()", "'ab'"),
        KindExample("toString(Sequence{'a', 'b'})", "'ab'"),
        KindExample("OrderedSet{'hello', 'world'}->toString()", "'helloworld'"),
        KindExample("Sequence{'a', Sequence{'b', OrderedSet{'c'}}, 1, true}->toString()", "'abc1true'"),
        KindExample("Sequence{}->toString()", "''"),
        KindExample("null.toString()", "''"),
        KindExample("null->toString()", "''"),
        KindExample("'x'.toString()", "'x'"),
        KindExample("1.toString()", "'1'"),
        KindExample("'x' + Sequence{'a', 'b'}", "'x' + Sequence{'a', 'b'}->toString()"),
    ]

    @Test("The text of a collection joins the text of its elements", arguments: texts)
    func text(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    @Test("Adding collections leaves the operands unchanged")
    func operandsUnchanged() async throws {
        let left = seq("a", "b")
        let right = seq("c")
        let result = try await AQLBinaryExpression(left: lit(left), op: .add, right: lit(right))
            .evaluate(in: makeContext(options: .standard))
        #expect(AQLValues.areEqual(result, seq("a", "b", "c")))
        #expect(AQLValues.elements(of: left)?.count == 2)
        #expect(AQLValues.elements(of: right)?.count == 1)
    }

    // MARK: Subtraction

    /// `-` and `sub` between two collections.
    nonisolated static let subtractions: [KindExample] = [
        KindExample("Sequence{'a', 'b', 'c'} - Sequence{'c', 'b', 'f'}", "Sequence{'a'}"),
        KindExample("Sequence{'a', 'b', 'c'} - OrderedSet{'c', 'b', 'f'}", "Sequence{'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'} - OrderedSet{'c', 'b', 'f'}", "OrderedSet{'a'}"),
        KindExample("Set{'a', 'b', 'c'} - Sequence{'b'}", "Set{'a', 'c'}"),
        KindExample("Bag{'a', 'b', 'a'} - Sequence{'b'}", "Bag{'a', 'a'}"),
        KindExample("Sequence{'a', 'b', 'a'} - Sequence{'a'}", "Sequence{'b'}"),
        KindExample("Sequence{'a', 'b'} - Sequence{}", "Sequence{'a', 'b'}"),
        KindExample("Sequence{'a', 'b', 'a'}->sub(Sequence{'a'})", "Sequence{'b'}"),
        KindExample("Sequence{'a', 'b', 'c'} - Sequence{'a'} - Sequence{'c'}", "Sequence{'b'}"),
        KindExample("3 - 1", "2"),
    ]

    @Test("Subtracting a collection removes every occurrence of its elements", arguments: subtractions)
    func subtraction(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    @Test(
        "Subtracting a value that is not a collection from a collection fails",
        arguments: ["Sequence{'a'} - 'a'", "'a' - Sequence{'a'}", "Sequence{1} - 1", "1 - Sequence{1}"])
    func invalidSubtraction(_ source: String) async throws {
        await #expect(throws: AQLExecutionError.self) { _ = try await AQLCollectionKindTests.value(of: source) }
    }

    // MARK: Union

    /// `union` of collections of each kind.
    nonisolated static let unions: [KindExample] = [
        KindExample("Sequence{'a', 'b', 'c'}->union(Sequence{'d', 'c'})", "Sequence{'a', 'b', 'c', 'd', 'c'}"),
        KindExample(
            "Sequence{'a', 'b', 'c', 'c', 'c'}->union(Sequence{'c', 'b', 'a'})",
            "Sequence{'a', 'b', 'c', 'c', 'c', 'c', 'b', 'a'}"),
        KindExample("Sequence{'a', 'b'}.union(Sequence{'b'})", "Sequence{'a', 'b', 'b'}"),
        KindExample("Sequence{}->union(Sequence{})", "Sequence{}"),
        KindExample("Bag{'a', 'b'}->union(Bag{'b'})", "Bag{'a', 'b', 'b'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->union(OrderedSet{'d', 'c'})", "OrderedSet{'a', 'b', 'c', 'd'}"),
        KindExample("Set{'a', 'b'}->union(Set{'b', 'c'})", "Set{'a', 'b', 'c'}"),
        KindExample("Sequence{'a', 'b'}->union(OrderedSet{'b', 'c'})", "Sequence{'a', 'b', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b'}->union(Sequence{'c', 'c'})", "OrderedSet{'a', 'b', 'c'}"),
    ]

    @Test("A union keeps repeated elements unless its receiver is a set", arguments: unions)
    func union(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }

    // MARK: Related operations on sequences and sets

    /// `concat`, `intersection`, `including` and `excluding` on sequences and sets.
    nonisolated static let relatedOperations: [KindExample] = [
        KindExample("Sequence{'a', 'b'}->concat(OrderedSet{'b', 'c'})", "Sequence{'a', 'b', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b'}->concat(Sequence{'b', 'c'})", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("Sequence{'a', 'b', 'a'}->intersection(Sequence{'a'})", "Sequence{'a', 'a'}"),
        KindExample("Sequence{'a', 'b'}->intersection(Sequence{'a', 'a'})", "Sequence{'a'}"),
        KindExample("Sequence{'c', 'b', 'a'}->intersection(Sequence{'a', 'b'})", "Sequence{'b', 'a'}"),
        KindExample("OrderedSet{'c', 'b', 'a'}->intersection(Sequence{'a', 'b', 'a'})", "OrderedSet{'b', 'a'}"),
        KindExample("Sequence{'a', 'b'}->including('a')", "Sequence{'a', 'b', 'a'}"),
        KindExample("OrderedSet{'a', 'b'}->including('a')", "OrderedSet{'a', 'b'}"),
        KindExample("Sequence{'a', 'b', 'a'}->excluding('a')", "Sequence{'b'}"),
        KindExample("OrderedSet{'a', 'b'}->excluding('a')", "OrderedSet{'b'}"),
        KindExample("Set{'a', 'b'}->excluding('c')", "Set{'a', 'b'}"),
    ]

    @Test("Related operations follow the kind of their receiver", arguments: relatedOperations)
    func relatedOperation(_ example: KindExample) async throws {
        try await AQLCollectionKindTests.check(example)
    }
}
