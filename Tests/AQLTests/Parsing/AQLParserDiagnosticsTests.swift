//
//  AQLParserDiagnosticsTests.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

import EMFBase

@testable import AQL

@Suite("AQL parser diagnostics")
struct AQLParserDiagnosticsTests {

    private func first(_ source: String) throws -> SourceDiagnostic {
        try #require(AQLParser().parse(source).diagnostics.first)
    }

    @Test("A valid expression has no diagnostics and all its tokens")
    func valid() {
        let result = AQLParser().parse("a + -- sum\n b")
        #expect(result.expression != nil)
        #expect(result.diagnostics.isEmpty)
        #expect(result.tokens.count == 4)
        #expect(result.tokens[2].isComment)
    }

    @Test("A syntax error is reported at the offending token")
    func unexpectedToken() throws {
        let diagnostic = try first("1 + )")
        #expect(diagnostic.code == AQLDiagnosticCode.unexpectedToken)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.range?.span == Span(line: 1, column: 5, offset: 4, length: 1))
        #expect(diagnostic.message.contains("Expected expression"))
        #expect(diagnostic.range?.start.line == 1 && diagnostic.range?.start.column == 5)
        #expect(diagnostic.range?.start.utf8Offset == 4 && diagnostic.range?.utf8Length == 1)
    }

    @Test("An error on a later line has its line and column")
    func laterLine() throws {
        let diagnostic = try first("a\n  + *")
        #expect(diagnostic.range?.start.line == 2)
        #expect(diagnostic.range?.start.column == 5)
        #expect(diagnostic.range?.start.utf8Offset == 6)
    }

    @Test("Running out of text is reported at the end")
    func unexpectedEnd() throws {
        let diagnostic = try first("f(1,\n")
        #expect(diagnostic.code == AQLDiagnosticCode.unexpectedEnd)
        #expect(diagnostic.range?.span == Span(line: 2, column: 1, offset: 5, length: 0))
    }

    @Test("Tokens after a complete expression are reported")
    func trailing() throws {
        let diagnostic = try first("1 2")
        #expect(diagnostic.code == AQLDiagnosticCode.trailingTokens)
        #expect(diagnostic.range?.span == Span(line: 1, column: 3, offset: 2, length: 1))
        #expect(try first("x )").code == AQLDiagnosticCode.trailingTokens)
    }

    @Test("A lexical problem is reported once, at its own position")
    func lexical() throws {
        let result = AQLParser().parse("a + 'oops")
        #expect(result.expression == nil)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].code == AQLDiagnosticCode.unterminatedString)
        #expect(result.diagnostics[0].range?.start.utf8Offset == 4)
    }

    @Test("A lexical problem and a syntax error at different places are both reported, in order")
    func lexicalAndSyntax() {
        let result = AQLParser().parse("1 + ) 'x")
        #expect(result.expression == nil)
        #expect(result.diagnostics.map(\.code) == [
            AQLDiagnosticCode.unexpectedToken, AQLDiagnosticCode.unterminatedString,
        ])
        #expect(result.diagnostics.map { $0.range?.start.utf8Offset } == [4, 6])
        #expect(AQLParser().parse("1 # +").diagnostics.map(\.code) == [AQLDiagnosticCode.invalidCharacter])
    }

    @Test("An empty text has an error at the start")
    func empty() throws {
        let diagnostic = try first("")
        #expect(diagnostic.code == AQLDiagnosticCode.unexpectedEnd)
        #expect(diagnostic.range?.span == Span(line: 1, column: 1, offset: 0, length: 0))
        #expect(try first("   -- only a comment").range?.start.utf8Offset == 20)
    }

    @Test("Each construct reports what it expected", arguments: [
        ("x.", "property name"),
        ("x->", "collection operation name"),
        ("if a then b else c", "endif"),
        ("if a b", "then"),
        ("let x 1 in 1", "'='"),
        ("let 1", "variable name"),
        ("a::", "name after '::'"),
        ("f(1 2)", "')'"),
        ("Sequence{1 2}", "'}'"),
        ("xs->select(x | x", "')'"),
        ("xs->indexOf 1", "'('"),
    ])
    func messages(source: String, expected: String) throws {
        let diagnostic = try first(source)
        #expect(diagnostic.message.contains(expected), "\(diagnostic.message)")
    }

    @Test("A syntax error carries a diagnostic and a description")
    func errorDescription() {
        let error = AQLSyntaxError(
            SourceDiagnostic(severity: .error, code: "c", message: "m", range: .at(line: 3, column: 4)))
        #expect(error.description == "Line 3, column 4: m")
        #expect(error == AQLSyntaxError(error.diagnostic))
    }
}

@Suite("AQL token cursor")
struct AQLTokenCursorTests {

    private func cursor(_ source: String, terminator: @escaping AQLTokenCursor.Terminator = { _, _ in false })
        -> AQLTokenCursor
    {
        AQLTokenCursor(
            tokens: AQLTokeniser.tokenise(source).tokens + [AQLToken(kind: .eof, range: .at(line: 1, column: 1))],
            terminator: terminator)
    }

    @Test("A cursor reads and looks ahead")
    func reading() {
        var cursor = cursor("a b")
        #expect(cursor.currentKind == .identifier("a"))
        #expect(cursor.peekKind() == .identifier("b"))
        #expect(cursor.peek(5) == nil)
        #expect(cursor.peek(-1) == nil)
        cursor.advance()
        cursor.advance()
        #expect(cursor.currentKind == .eof)
        cursor.advance()
        #expect(cursor.current == nil)
        #expect(cursor.currentKind == .eof)
        #expect(cursor.atTerminator)
    }

    @Test("Parsing stops after the expression and leaves the cursor on the next token")
    func parsingFromCursor() throws {
        var cursor = cursor("a + b ) rest")
        var delegate = AQLDefaultParserDelegate()
        let expression = try AQLParser.parseExpression(&cursor, delegate: &delegate)
        #expect(AQLTreePrinter().print(expression) == "binary(+, var(a), var(b))")
        #expect(cursor.currentKind == .rightParen)
    }

    @Test("The host terminator decides whether a slash divides")
    func terminator() throws {
        let slashBeforeBracket: AQLTokenCursor.Terminator = { token, next in
            token.kind == .slash && next?.kind == .rightBracket
        }
        var delegate = AQLDefaultParserDelegate()

        var dividing = AQLTokenCursor(
            tokens: [
                AQLToken(kind: .identifier("a"), range: .at(line: 1, column: 1)),
                AQLToken(kind: .slash, range: .at(line: 1, column: 2)),
                AQLToken(kind: .identifier("b"), range: .at(line: 1, column: 3)),
                AQLToken(kind: .rightBracket, range: .at(line: 1, column: 4)),
                AQLToken(kind: .eof, range: .at(line: 1, column: 5)),
            ], terminator: slashBeforeBracket)
        let divided = try AQLParser.parseExpression(&dividing, delegate: &delegate)
        #expect(AQLTreePrinter().print(divided) == "binary(/, var(a), var(b))")
        #expect(dividing.currentKind == .rightBracket)

        var ending = AQLTokenCursor(
            tokens: [
                AQLToken(kind: .identifier("a"), range: .at(line: 1, column: 1)),
                AQLToken(kind: .slash, range: .at(line: 1, column: 2)),
                AQLToken(kind: .rightBracket, range: .at(line: 1, column: 3)),
                AQLToken(kind: .eof, range: .at(line: 1, column: 4)),
            ], terminator: slashBeforeBracket)
        let single = try AQLParser.parseExpression(&ending, delegate: &delegate)
        #expect(AQLTreePrinter().print(single) == "var(a)")
        #expect(ending.currentKind == .slash)
    }

    @Test("A host can start inside an implicit receiver context")
    func initialImplicitReceiver() throws {
        var cursor = AQLTokenCursor(
            tokens: AQLTokeniser.tokenise("f()").tokens + [AQLToken(kind: .eof, range: .at(line: 1, column: 4))],
            implicitReceiverDepth: 1)
        var delegate = AQLDefaultParserDelegate()
        let expression = try AQLParser.parseExpression(&cursor, delegate: &delegate)
        #expect(AQLTreePrinter().print(expression) == "call(var(self), f, arrow: false, args: [])")
        #expect(cursor.implicitReceiverDepth == 1)
    }

    @Test("Names, qualified names and types can be read on their own")
    func names() throws {
        var cursor = cursor("pkg::Type(Inner, a::B) , in")
        #expect(try AQLParser.parseTypeName(&cursor) == "pkg::Type(Inner, a::B)")
        #expect(cursor.currentKind == .comma)
        cursor.advance()
        #expect(try AQLParser.parseNameSegment(&cursor, describing: "name") == "in")

        var qualified = self.cursor("a::if::c")
        #expect(try AQLParser.parseQualifiedName(&qualified, describing: "name") == "a::if::c")

        var bad = self.cursor("(")
        #expect(throws: AQLSyntaxError.self) { try AQLParser.parseNameSegment(&bad, describing: "name") }
        var badType = self.cursor("a::")
        #expect(throws: AQLSyntaxError.self) { try AQLParser.parseTypeName(&badType) }
    }

    @Test("Call arguments can be read on their own")
    func callArguments() throws {
        var cursor = cursor("(x | x, 2) tail")
        var delegate = AQLDefaultParserDelegate()
        let arguments = try AQLParser.parseCallArguments(&cursor, delegate: &delegate, forOperation: "f")
        #expect(AQLTreePrinter().list(arguments) == "[lambda(x, var(x)), lit(int(2))]")
        #expect(cursor.currentKind == .identifier("tail"))

        var types = self.cursor("(a::B::C)")
        let typeArguments = try AQLParser.parseCallArguments(
            &types, delegate: &delegate, forOperation: "oclIsKindOf")
        #expect(AQLTreePrinter().list(typeArguments) == "[type(a::B, C)]")
    }
}
