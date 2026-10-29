//
//  AQLCollectionAddServicesTests.swift
//  AQL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

@MainActor
@Suite("AQL Collection element-adding services")
struct AQLCollectionAddServicesTests {
    nonisolated static let abc = seq("a", "b", "c")
    nonisolated static let de = seq("d", "e")

    nonisolated static let cases: [LibraryCase] = [
        LibraryCase(abc, "including", "d", expect: seq("a", "b", "c", "d")),
        LibraryCase(abc, "append", "f", expect: seq("a", "b", "c", "f")),
        LibraryCase(abc, "prepend", "f", expect: seq("f", "a", "b", "c")),
        LibraryCase(abc, "insertAt", 2, "f", expect: seq("a", "f", "b", "c")),
        LibraryCase(abc, "excluding", "c", expect: seq("a", "b")),
        LibraryCase(abc, "union", seq("d", "c"), expect: seq("a", "b", "c", "d")),
        LibraryCase(abc, "intersection", seq("a", "f"), expect: seq("a")),
        LibraryCase(abc, "sub", seq("c", "b", "f"), expect: seq("a")),
        LibraryCase(abc, "concat", de, expect: seq("a", "b", "c", "d", "e")),
        LibraryCase(abc, "count", "a", expect: 1),
        LibraryCase(abc, "count", "d", expect: 0),
        LibraryCase(seq(1, 2, 3, 4), "indexOf", 3, expect: 3),
        LibraryCase(seq(1, 2, 3, 4, 3), "lastIndexOf", 3, expect: 5),
        LibraryCase(abc, "subSequence", 1, 2, expect: seq("a", "b")),
        LibraryCase(abc, "subOrderedSet", 1, 2, expect: seq("a", "b")),
        LibraryCase(abc, "drop", 2, expect: seq("c")),
    ]

    @Test("Acceleo examples for the element-adding services", arguments: cases)
    func acceleoExamples(_ test: LibraryCase) async throws {
        try await check(test)
    }

    nonisolated static let collectionArguments: [LibraryCase] = [
        LibraryCase(abc, "including", de, expect: seq("a", "b", "c", de)),
        LibraryCase(abc, "append", de, expect: seq("a", "b", "c", de)),
        LibraryCase(abc, "prepend", de, expect: seq(de, "a", "b", "c")),
        LibraryCase(abc, "insertAt", 2, de, expect: seq("a", de, "b", "c")),
        LibraryCase(seq(), "including", de, expect: seq(de)),
        LibraryCase(seq(), "append", seq(), expect: seq(seq())),
        LibraryCase(seq(), "prepend", seq(), expect: seq(seq())),
        LibraryCase(seq(abc, de), "excluding", de, expect: seq(abc)),
        LibraryCase(seq(abc, de), "count", de, expect: 1),
        LibraryCase(seq(abc, de), "indexOf", de, expect: 2),
    ]

    @Test("A collection argument is added as a single element", arguments: collectionArguments)
    func collectionArgument(_ test: LibraryCase) async throws {
        try await check(test)
    }

    @Test("A collection argument is added whole through both call forms", arguments: ["including", "append"])
    func bothCallForms(_ name: String) async throws {
        let dot = try await evaluate(LibraryCase(Self.abc, name, Self.de, expect: nil))
        let arrow = try await evaluate(LibraryCase(Self.abc, name, Self.de, expect: nil, arrow: true))
        #expect(AQLValues.elements(of: dot)?.count == 4)
        #expect(AQLValues.areEqual(dot, arrow))
    }

    @Test("The receiver is not modified by adding a collection")
    func receiverUnchanged() async throws {
        _ = try await evaluate(LibraryCase(Self.abc, "append", Self.de, expect: nil))
        #expect(AQLValues.elements(of: Self.abc)?.count == 3)
    }
}
