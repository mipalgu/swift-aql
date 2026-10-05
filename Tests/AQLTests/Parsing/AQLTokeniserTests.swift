//
//  AQLTokeniserTests.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import AQL

@Suite("AQL tokeniser")
struct AQLTokeniserTests {

    private func kinds(_ source: String) -> [AQLTokenKind] {
        AQLSyntax.tokens(in: source).map(\.kind)
    }

    @Test("Punctuation and operators")
    func punctuation() {
        #expect(
            kinds("( ) , : :: . | ? { } / + - * = <> < > <= >= ->") == [
                .leftParen, .rightParen, .comma, .colon, .doubleColon, .dot, .pipe, .questionMark,
                .leftBrace, .rightBrace, .slash, .operator("+"), .operator("-"), .operator("*"),
                .operator("="), .operator("<>"), .operator("<"), .operator(">"), .operator("<="),
                .operator(">="), .operator("->"),
            ])
    }

    @Test("Words are keywords, literals or identifiers")
    func words() {
        #expect(
            kinds("if x_1 true false null select Foo mod") == [
                .keyword("if"), .identifier("x_1"), .booleanLiteral(true), .booleanLiteral(false),
                .keyword("null"), .keyword("select"), .identifier("Foo"), .keyword("mod"),
            ])
    }

    @Test("Numbers")
    func numbers() {
        #expect(kinds("1 23 4.5 ( -6 , -7.5") == [
            .integerLiteral(1), .integerLiteral(23), .realLiteral(4.5), .leftParen, .integerLiteral(-6),
            .comma, .realLiteral(-7.5),
        ])
        #expect(kinds("1.x") == [.integerLiteral(1), .dot, .identifier("x")])
    }

    @Test("A minus after an operand is an operator, after an operator a sign")
    func minusAfterOperand() {
        #expect(kinds("a -1") == [.identifier("a"), .operator("-"), .integerLiteral(1)])
        #expect(kinds("(a) -1") == [.leftParen, .identifier("a"), .rightParen, .operator("-"), .integerLiteral(1)])
        #expect(kinds("a - -1") == [.identifier("a"), .operator("-"), .integerLiteral(-1)])
        #expect(kinds("and -1") == [.keyword("and"), .integerLiteral(-1)])
        #expect(kinds("size -1") == [.keyword("size"), .operator("-"), .integerLiteral(1)])
        #expect(kinds("1 -> 2") == [.integerLiteral(1), .operator("->"), .integerLiteral(2)])
    }

    @Test("Strings resolve escapes and doubled quotes")
    func strings() {
        #expect(kinds("'it''s'") == [.stringLiteral("it's")])
        #expect(kinds(#"'a\n\t\r\b\f\\\'\"x'"#) == [.stringLiteral("a\n\t\r\u{08}\u{0C}\\'\"x")])
        #expect(kinds(#"'Aé'"#) == [.stringLiteral("Aé")])
        #expect(kinds(#"'😀'"#) == [.stringLiteral("😀")])
        #expect(kinds(#"'\ud83dx'"#) == [.stringLiteral("\u{FFFD}x")])
        #expect(kinds(#"'\ud83dA'"#) == [.stringLiteral("\u{FFFD}A")])
        #expect(kinds(#"'\q'"#) == [.stringLiteral("q")])
    }

    @Test("Comments run to the end of the line and are trimmed")
    func comments() {
        #expect(kinds("a -- note  \nb") == [.identifier("a"), .comment("note"), .identifier("b")])
        #expect(kinds("-- ") == [.comment("")])
    }

    @Test("Invalid text becomes invalid tokens and diagnostics")
    func invalidTokens() {
        let unterminated = AQLTokeniser.tokenise("a 'oops")
        #expect(unterminated.tokens.map(\.kind) == [.identifier("a"), .invalid("'oops")])
        #expect(unterminated.diagnostics.map(\.code) == [AQLDiagnosticCode.unterminatedString])
        #expect(unterminated.diagnostics.first?.span == AQLSourceSpan(line: 1, column: 3, offset: 2, length: 5))

        let escape = AQLTokeniser.tokenise(#"'\u12'"#)
        #expect(escape.diagnostics.map(\.code) == [AQLDiagnosticCode.malformedEscape])
        #expect(escape.tokens.count == 1 && escape.tokens[0].isInvalid)

        let character = AQLTokeniser.tokenise("a # b")
        #expect(character.tokens.map(\.kind) == [.identifier("a"), .invalid("#"), .identifier("b")])
        #expect(character.diagnostics.map(\.code) == [AQLDiagnosticCode.invalidCharacter])

        let number = AQLTokeniser.tokenise("99999999999999999999")
        #expect(number.diagnostics.map(\.code) == [AQLDiagnosticCode.invalidNumber])
        #expect(number.tokens.count == 1 && number.tokens[0].isInvalid)

        let backslash = AQLTokeniser.tokenise("'abc\\")
        #expect(backslash.diagnostics.map(\.code) == [AQLDiagnosticCode.unterminatedString])
    }

    @Test("Tokens carry line, column, UTF-8 offset and length")
    func positions() {
        let tokens = AQLSyntax.tokens(in: "ab +\n  'é' -- c")
        #expect(tokens.map(\.span) == [
            AQLSourceSpan(line: 1, column: 1, offset: 0, length: 2),
            AQLSourceSpan(line: 1, column: 4, offset: 3, length: 1),
            AQLSourceSpan(line: 2, column: 3, offset: 7, length: 4),
            AQLSourceSpan(line: 2, column: 7, offset: 12, length: 4),
        ])
        #expect(tokens[2].span.endOffset == 11)
    }

    @Test("Line breaks of every style start a new line")
    func lineBreaks() {
        let tokens = AQLSyntax.tokens(in: "a\r\nb\rc\nd")
        #expect(tokens.map(\.span.line) == [1, 2, 3, 4])
        #expect(tokens.map(\.span.column) == [1, 1, 1, 1])
    }

    @Test("Highlighting covers all non-blank text, including comments and invalid text")
    func coverage() {
        let source = "let x = 'a' in -- why\n  x + # + 1.5 / foo(::)"
        let tokens = AQLSyntax.tokens(in: source)
        let utf8 = Array(source.utf8)
        var covered = Array(repeating: false, count: utf8.count)
        for token in tokens {
            for index in token.span.offset..<token.span.endOffset {
                #expect(!covered[index])
                covered[index] = true
            }
        }
        let blanks = Set(" \n".utf8)
        for (index, byte) in utf8.enumerated() where !blanks.contains(byte) {
            #expect(covered[index], "byte \(index) is not covered")
        }
        #expect(tokens.contains { $0.isComment })
        #expect(tokens.contains { $0.isInvalid })
    }

    @Test("Highlighting never throws on arbitrary text")
    func neverThrows() {
        for source in ["", "'", "\\", "((((", "\u{0}", "é-é", "-", "--", "..", "'\\u'", "'\\ud800"] {
            _ = AQLSyntax.tokens(in: source)
        }
        #expect(AQLSyntax.tokens(in: "").isEmpty)
    }

    @Test("Token kinds describe themselves for messages")
    func descriptions() {
        let kinds: [AQLTokenKind] = [
            .leftParen, .rightParen, .comma, .colon, .doubleColon, .dot, .pipe, .questionMark,
            .leftBrace, .rightBrace, .leftBracket, .rightBracket, .slash, .keyword("if"),
            .identifier("x"), .stringLiteral("s"), .integerLiteral(1), .realLiteral(1.5),
            .booleanLiteral(true), .operator("+"), .comment("c"), .invalid("#"), .other, .eof,
        ]
        let descriptions = kinds.map(\.description)
        #expect(Set(descriptions).count == kinds.count)
        #expect(descriptions.allSatisfy { !$0.isEmpty })
    }

    @Test("The keyword set is the structural keywords and the operation names")
    func keywordSet() {
        #expect(AQLSyntax.keywords == AQLSyntax.structuralKeywords.union(AQLSyntax.operationKeywords))
        #expect(!AQLSyntax.keywords.contains("true"))
        #expect(AQLSyntax.typeArgumentOperationNames.isSuperset(of: AQLSyntax.typeOperationNames))
        #expect(AQLSyntax.collectionTypeNames == AQLBuiltInType.collections)
    }
}
