//
//  AQLParserGoldenTests.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import AQL

/// Compares the trees of the standalone parser with the goldens recorded from the template
/// language parser that the grammar was extracted from.
@Suite("AQL parser goldens")
struct AQLParserGoldenTests {

    @Test("Every corpus expression has a golden and every golden a corpus expression")
    func corpusAndGoldensAgree() {
        let sources = AQLExpressionCorpus.valid.map(\.source)
        #expect(Set(sources).count == sources.count)
        #expect(Set(sources) == Set(AQLExpressionGoldens.trees.keys))
    }

    @Test("A corpus expression parses to its golden tree", arguments: AQLExpressionCorpus.valid.map(\.source))
    func parsesToGolden(source: String) {
        var delegate = HostProbeDelegate()
        let result = AQLParser().parse(source, delegate: &delegate)
        #expect(result.diagnostics.isEmpty)
        #expect(result.expression.map(AQLParserTestSupport.printer.print) == AQLExpressionGoldens.trees[source])
    }

    @Test("A malformed expression is rejected with a diagnostic", arguments: AQLExpressionCorpus.invalid)
    func rejectsMalformed(source: String) {
        let result = AQLParser().parse(source)
        #expect(result.expression == nil)
        #expect(!result.diagnostics.isEmpty)
    }

    @Test("Without a delegate every call is a plain AQL call")
    func plainCalls() {
        #expect(AQLParserTestSupport.plainTree("f(1)") == "call(-, f, arrow: false, args: [lit(int(1))])")
        #expect(
            AQLParserTestSupport.plainTree("x.f(1)")
                == "call(var(x), f, arrow: false, args: [lit(int(1))])")
    }

    @Test("A bare call inside an iterator body applies to self, except standalone functions")
    func implicitReceiver() {
        #expect(
            AQLParserTestSupport.plainTree("xs->select(f())")
                == "collection(select, var(xs), iterator: self, body: "
                + "call(var(self), f, arrow: false, args: []))")
        #expect(
            AQLParserTestSupport.plainTree("xs->select(x | f())")
                == "collection(select, var(xs), iterator: x, body: call(-, f, arrow: false, args: []))")
        #expect(
            AQLParserTestSupport.plainTree("xs->select(abs(1) > 0)")
                == "collection(select, var(xs), iterator: self, body: binary(>, "
                + "call(-, abs, arrow: false, args: [lit(int(1))]), lit(int(0))))")
    }

    @Test("The implicit receiver ends with the iterator body")
    func implicitReceiverScope() {
        #expect(
            AQLParserTestSupport.plainTree("xs->select(f()) = f()")?.hasSuffix("call(-, f, arrow: false, args: []))")
                == true)
    }

    @Test("Qualified names are types inside type operation arguments")
    func typeArgumentDepth() {
        #expect(AQLParserTestSupport.plainTree("x.oclIsKindOf(a::B::C)")?.contains("type(a::B, C)") == true)
        #expect(AQLParserTestSupport.plainTree("a::B::C")?.hasPrefix("enum(a, B, C)") == true)
        #expect(AQLParserTestSupport.plainTree("x.oclIsKindOf(a::B::C) = a::B::C")?.hasSuffix("enum(a, B, C))") == true)
    }

    @Test("A host construct is offered each name before the grammar reads it")
    func hostPrimary() {
        var delegate = HostProbeDelegate()
        let result = AQLParser().parse("collected('a') + f(x)", delegate: &delegate)
        #expect(result.diagnostics.isEmpty)
        #expect(delegate.offered == ["collected", "f", "x"])
        #expect(
            result.expression.map(AQLParserTestSupport.printer.print)
                == "binary(+, collected(lit(string(\"a\"))), invoke(-, f, args: [var(x)]))")
    }

    @Test("A host construct may nest other expressions, including its own")
    func hostPrimaryNesting() {
        #expect(
            AQLParserTestSupport.tree("collected(collected('a'))")
                == "collected(collected(lit(string(\"a\"))))")
    }

    @Test("Null-safe navigation is not part of the grammar")
    func nullSafeNavigation() {
        #expect(AQLParser().parse("a?.b").expression == nil)
    }

    @Test("A host construct reports a malformed construct at the offending token")
    func hostPrimaryError() {
        var delegate = HostProbeDelegate()
        let result = AQLParser().parse("collected('a' 'b')", delegate: &delegate)
        #expect(result.expression == nil)
        #expect(result.diagnostics.first?.span.offset == 14)
        #expect(result.diagnostics.first?.message.contains("Expected ')'") == true)
    }
}
