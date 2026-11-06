//
//  AQLStrictModeTests.swift
//  AQL
//
//  Created by Rene Hexel on 5/11/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// An expression that Eclipse AQL rejects, with the value it has outside strict mode.
struct LenientExample: Sendable, CustomTestStringConvertible {
    /// The expression under test.
    let source: String
    /// The expression denoting its value outside strict mode under ``AQLOptions/standard``.
    let lenient: String

    init(_ source: String, lenient: String) {
        self.source = source
        self.lenient = lenient
    }

    var testDescription: String { source }
}

@MainActor
@Suite("AQL strict mode")
struct AQLStrictModeTests {

    /// The standard options in strict mode.
    static let strict = AQLOptions(strict: true)

    /// Expressions that strict mode rejects, with their values otherwise.
    nonisolated static let rejected: [LenientExample] = [
        LenientExample("Sequence{'a', 'b'}->union(OrderedSet{'b', 'c'})", lenient: "Sequence{'a', 'b', 'b', 'c'}"),
        LenientExample("OrderedSet{'a', 'b'}->union(Sequence{'c', 'c'})", lenient: "OrderedSet{'a', 'b', 'c'}"),
        LenientExample("Set{'a'}->union(Bag{'b'})", lenient: "Set{'a', 'b'}"),
        LenientExample("Bag{'a'}->union(Set{'b'})", lenient: "Bag{'a', 'b'}"),
        LenientExample("'a'->union(Sequence{'b'})", lenient: "Set{'a', 'b'}"),
        LenientExample("Sequence{'a'}->union('b')", lenient: "Sequence{'a', 'b'}"),
        LenientExample("Sequence{'a'}->union(null)", lenient: "Sequence{'a'}"),
        LenientExample("Sequence{'a'}->concat('b')", lenient: "Sequence{'a', 'b'}"),
        LenientExample("Sequence{'a'}->concat(null)", lenient: "Sequence{'a'}"),
        LenientExample("Sequence{'a'}->addAll('b')", lenient: "Sequence{'a', 'b'}"),
        LenientExample("Sequence{'a', 'b'}->sub('a')", lenient: "Sequence{'b'}"),
        LenientExample("Sequence{'a', 'b'}->difference('a')", lenient: "Sequence{'b'}"),
        LenientExample("Sequence{'a', 'b'}->removeAll(null)", lenient: "Sequence{'a', 'b'}"),
        LenientExample("Sequence{'a', 'b'}->intersection('a')", lenient: "Sequence{'a'}"),
        LenientExample("Sequence{'a', 'b'}->includesAll('a')", lenient: "true"),
        LenientExample("Sequence{'a', 'b'}->excludesAll('c')", lenient: "true"),
        LenientExample("Sequence{'a', 'b'}->includesAll(null)", lenient: "true"),
    ]

    @Test("Strict mode rejects what Eclipse AQL rejects", arguments: rejected)
    func rejects(_ example: LenientExample) async throws {
        let context = makeContext(options: Self.strict)
        await #expect(throws: AQLExecutionError.self) {
            _ = try await AQLCollectionKindTests.value(of: example.source, in: context)
        }
    }

    @Test("Outside strict mode the same expressions are accepted", arguments: rejected)
    func acceptsByDefault(_ example: LenientExample) async throws {
        try await AQLCollectionKindTests.check(KindExample(example.source, example.lenient))
    }

    /// Expressions that strict mode accepts, with their values.
    nonisolated static let accepted: [KindExample] = [
        KindExample("Sequence{'a'}->union(Sequence{'a'})", "Sequence{'a', 'a'}"),
        KindExample("Bag{'a'}->union(Sequence{'b'})", "Bag{'a', 'b'}"),
        KindExample("OrderedSet{'a'}->union(Set{'a', 'b'})", "OrderedSet{'a', 'b'}"),
        KindExample("Sequence{'a'}->concat(OrderedSet{'b'})", "Sequence{'a', 'b'}"),
        KindExample("OrderedSet{'a', 'b'}->sub(Sequence{'a'})", "OrderedSet{'b'}"),
        KindExample("Sequence{'a', 'b'}->intersection(Set{'b'})", "Sequence{'b'}"),
        KindExample("Sequence{'a', 'b'}->includesAll(Sequence{})", "true"),
        KindExample("Sequence{'a'} + OrderedSet{'b'}", "Sequence{'a', 'b'}"),
        KindExample("Sequence{'a'} - OrderedSet{'a'}", "Sequence{}"),
        KindExample("Sequence{'a'} + 'b'", "'ab'"),
        KindExample("Sequence{'a'}.add(null)", "Sequence{'a'}"),
        KindExample("Sequence{'a'}->add(null)", "'a'"),
        KindExample("Sequence{'a'}->including('b')", "Sequence{'a', 'b'}"),
        KindExample("Sequence{'a'}->excluding('a')", "Sequence{}"),
    ]

    @Test("Strict mode accepts what Eclipse AQL accepts", arguments: accepted)
    func accepts(_ example: KindExample) async throws {
        let context = makeContext(options: Self.strict)
        let result = try await AQLCollectionKindTests.value(of: example.source, in: context)
        let expected = try await AQLCollectionKindTests.value(of: example.expected)
        #expect(AQLValues.areEqual(result, expected), "got \(AQLValues.description(of: result))")
        #expect(AQLCollectionKindTests.kind(result) == AQLCollectionKindTests.kind(expected))
    }

    @Test("With every collection a sequence, strict mode only rejects arguments that are not collections")
    func strictSequences() async throws {
        var options = AQLOptions.legacy
        options.strict = true
        let context = makeContext(options: options)
        let union = try await AQLCollectionKindTests.value(
            of: "OrderedSet{'a'}->union(Sequence{'b'})", in: context)
        #expect(AQLValues.areEqual(union, seq("a", "b")))
        await #expect(throws: AQLExecutionError.self) {
            _ = try await AQLCollectionKindTests.value(of: "Sequence{'a'}->concat('b')", in: context)
        }
    }

    @Test("The error names the service")
    func errorNamesService() async throws {
        let context = makeContext(options: Self.strict)
        do {
            _ = try await AQLCollectionKindTests.value(of: "Sequence{'a'}->sub('a')", in: context)
            Issue.record("expected an error")
        } catch let AQLExecutionError.typeError(message) {
            #expect(message.contains("sub"))
        }
    }
}
