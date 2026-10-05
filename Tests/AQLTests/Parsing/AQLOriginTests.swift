//
//  AQLOriginTests.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import AQL

@Suite("AQL expression origins")
struct AQLOriginTests {

    /// The source text that a node's origin covers.
    private func text(of expression: any AQLExpression, in source: String) -> String? {
        guard let range = expression.origin.range else { return nil }
        let bytes = Array(source.utf8)
        return String(decoding: bytes[range.start.utf8Offset..<range.end.utf8Offset], as: UTF8.self)
    }

    private func parse(_ source: String) throws -> any AQLExpression {
        try #require(AQLParser().parse(source).expression)
    }

    @Test("Every parsed node covers exactly the text it was parsed from", arguments: [
        ("a + b * c", "a + b * c"),
        ("-x", "-x"),
        ("not  x", "not  x"),
        ("a.b.c", "a.b.c"),
        ("a.f(1, 2)", "a.f(1, 2)"),
        ("f(1)", "f(1)"),
        ("xs->select(x | x > 1)", "xs->select(x | x > 1)"),
        ("xs->size()", "xs->size()"),
        ("xs->indexOf(1)", "xs->indexOf(1)"),
        ("xs->union(ys)", "xs->union(ys)"),
        ("if a then b else c endif", "if a then b else c endif"),
        ("let x = 1 in x", "let x = 1 in x"),
        ("Sequence{1, 2}", "Sequence{1, 2}"),
        ("p::T", "p::T"),
        ("p::E::l", "p::E::l"),
        ("'text'", "'text'"),
        ("42", "42"),
        ("null", "null"),
        ("a implies b", "a implies b"),
    ])
    func rootOrigin(source: String, expected: String) throws {
        #expect(text(of: try parse(source), in: source) == expected)
    }

    @Test("Operands keep their own origins")
    func operands() throws {
        let source = "alpha +\n  beta"
        let binary = try #require(try parse(source) as? AQLBinaryExpression)
        #expect(text(of: binary.left, in: source) == "alpha")
        #expect(text(of: binary.right, in: source) == "beta")
        #expect(binary.right.origin.range?.start.line == 2)
        #expect(binary.right.origin.range?.start.column == 3)
    }

    @Test("Lambdas and call arguments have origins")
    func lambdas() throws {
        let source = "f(x | x + 1, 2)"
        let call = try #require(try parse(source) as? AQLCallExpression)
        #expect(text(of: call.arguments[0], in: source) == "x | x + 1")
        #expect(text(of: call.arguments[1], in: source) == "2")
    }

    @Test("A parenthesised expression has the origin of its content")
    func parentheses() throws {
        let source = "(a)"
        #expect(text(of: try parse(source), in: source) == "a")
    }

    @Test("Origins do not affect equality")
    func equality() {
        let range = SourceRange(start: .start, end: SourcePosition(utf8Offset: 3, line: 1, column: 4))
        #expect(SourceOrigin(range) == SourceOrigin())
    }

    @Test("Nodes built in code have no range")
    func builtInCode() {
        #expect(AQLVariableExpression(name: "a").origin.range == nil)
        let origin = SourceOrigin(.at(line: 1, column: 1))
        #expect(AQLVariableExpression(name: "a", origin: origin).origin.range != nil)
    }

    @Test("Host nodes without an origin report none")
    func hostNodes() {
        let probe = CollectedProbe(setName: AQLLiteralExpression(value: "s"))
        #expect(probe.origin.range == nil)
    }
}

@Suite("AQL highlighting tokens")
struct AQLHighlightTokenTests {

    private func kinds(_ source: String) -> [SourceTokenKind] {
        AQLSyntax.tokens(in: source).map(\.kind)
    }

    @Test("Token kinds map to highlighting kinds")
    func mapping() {
        #expect(kinds("if x then 1 else 2.5 endif") == [
            .keyword, .identifier, .keyword, .number, .keyword, .number, .keyword,
        ])
        #expect(kinds("'a' true a + b -- c") == [
            .string, .boolean, .identifier, .operator, .identifier, .comment,
        ])
        #expect(kinds("Sequence{x}") == [.typeName, .punctuation, .identifier, .punctuation])
        #expect(kinds("#") == [.invalid])
        #expect(AQLTokenKind.other.highlightKind == .text)
    }

    @Test("Columns count Unicode scalars and ranges end where the token ends")
    func columns() {
        let tokens = AQLSyntax.tokens(in: "'é😀' + x")
        #expect(tokens[1].range.start.column == 6)
        #expect(tokens[0].range.end.column == 5)
        #expect(tokens[0].range.end.utf8Offset == 8)
    }

    @Test("Multi-line tokens end on a later line")
    func multiLine() {
        let tokens = AQLSyntax.tokens(in: "'a\nb' c")
        #expect(tokens[0].range.start.line == 1)
        #expect(tokens[0].range.end.line == 2)
        #expect(tokens[0].range.end.column == 3)
    }
}
