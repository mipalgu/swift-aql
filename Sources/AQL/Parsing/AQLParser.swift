//
//  AQLParser.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// The outcome of parsing a piece of AQL text.
public struct AQLParseResult: Sendable {
    /// The parsed expression, or `nil` if the text has a syntax error.
    public var expression: (any AQLExpression)?

    /// The problems found, in order of position. Empty if and only if ``expression`` is not `nil`.
    public var diagnostics: [AQLDiagnostic]

    /// The tokens of the text, including comments and invalid tokens but not the end of input.
    public var tokens: [AQLToken]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - expression: The parsed expression, if any.
    ///   - diagnostics: The problems found.
    ///   - tokens: The tokens of the text.
    public init(expression: (any AQLExpression)?, diagnostics: [AQLDiagnostic], tokens: [AQLToken]) {
        self.expression = expression
        self.diagnostics = diagnostics
        self.tokens = tokens
    }
}

/// Parses AQL expressions.
///
/// A piece of AQL text holds exactly one expression. ``parse(_:)`` reads such text on its own.
/// Hosts that embed AQL expressions in a larger syntax read their tokens through an
/// ``AQLTokenCursor`` with ``parseExpression(_:delegate:)`` and shape the result through an
/// ``AQLParserDelegate``.
///
/// The grammar follows OCL: `implies` binds loosest, then `or` and `xor`, `and`, comparison,
/// addition, multiplication (including `mod` and `div`), unary `not` and `-`, and finally
/// navigation with `.` and `->`. Primary expressions are literals, names, qualified names,
/// calls, collection literals such as `Sequence{1, 2}`, parenthesised expressions,
/// `if ... then ... else ... endif`, and `let ... in ...`. Comments start with `--` and run to
/// the end of the line.
public struct AQLParser: Sendable {

    /// Creates a parser.
    public init() {}

    /// Parses one expression from text.
    ///
    /// Parsing stops at the first syntax error, which is reported with the position of the
    /// offending token. Lexical problems (unterminated strings, unknown characters) are
    /// reported as well, so the diagnostics can hold several entries even though parsing
    /// stops at the first.
    ///
    /// - Parameter source: The AQL text.
    /// - Returns: The expression, or `nil` with diagnostics if the text is not a single valid
    ///   expression; and the tokens of the text.
    public func parse(_ source: String) -> AQLParseResult {
        var delegate = AQLDefaultParserDelegate()
        return parse(source, delegate: &delegate)
    }

    /// Parses one expression from text, shaping the result through a delegate.
    ///
    /// - Parameters:
    ///   - source: The AQL text.
    ///   - delegate: The host hooks.
    /// - Returns: The expression, or `nil` with diagnostics if the text is not a single valid
    ///   expression; and the tokens of the text.
    public func parse(_ source: String, delegate: inout some AQLParserDelegate) -> AQLParseResult {
        let tokenisation = AQLTokeniser.tokenise(source)
        var diagnostics = tokenisation.diagnostics
        let endToken = AQLToken(kind: .eof, span: Self.endSpan(of: source))
        var cursor = AQLTokenCursor(
            tokens: tokenisation.tokens.filter { !$0.isComment } + [endToken])

        var expression: (any AQLExpression)?
        do {
            let parsed = try Self.parseExpression(&cursor, delegate: &delegate)
            if cursor.currentKind == .eof {
                expression = parsed
            } else {
                throw AQLSyntaxError(
                    AQLDiagnostic(
                        code: AQLDiagnosticCode.trailingTokens,
                        message: "Unexpected \(cursor.currentKind) after the expression",
                        span: cursor.errorSpan))
            }
        } catch let error as AQLSyntaxError {
            let alreadyReported = diagnostics.contains { $0.span.offset == error.diagnostic.span.offset }
            if !alreadyReported { diagnostics.append(error.diagnostic) }
        } catch {
            // The grammar only throws syntax errors.
        }
        if expression != nil && !diagnostics.isEmpty { expression = nil }
        diagnostics.sort { $0.span.offset < $1.span.offset }
        return AQLParseResult(expression: expression, diagnostics: diagnostics, tokens: tokenisation.tokens)
    }

    /// The span of the end of the text.
    private static func endSpan(of source: String) -> AQLSourceSpan {
        var line = 1
        var column = 1
        for character in source {
            if character.isNewline {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return AQLSourceSpan(line: line, column: column, offset: source.utf8.count, length: 0)
    }

    // MARK: - Reading from a host's tokens

    /// Parses an expression starting at the cursor.
    ///
    /// On return the cursor is positioned after the expression. On failure its position is
    /// where the problem was found.
    ///
    /// - Parameters:
    ///   - cursor: The tokens and position to read from.
    ///   - delegate: The host hooks.
    /// - Returns: The expression.
    /// - Throws: ``AQLSyntaxError`` if the tokens do not start with a valid expression.
    public static func parseExpression(
        _ cursor: inout AQLTokenCursor, delegate: inout some AQLParserDelegate
    ) throws -> any AQLExpression {
        try withGrammar(&cursor, &delegate) { try $0.parseExpression() }
    }

    /// Parses the argument list of a call, starting at the opening parenthesis.
    ///
    /// Arguments may be lambdas such as `x | body`; arguments of type operations denote types.
    ///
    /// - Parameters:
    ///   - cursor: The tokens and position to read from.
    ///   - delegate: The host hooks.
    ///   - operation: The name of the operation being called, if any.
    /// - Returns: The argument expressions.
    /// - Throws: ``AQLSyntaxError`` if the arguments are malformed.
    public static func parseCallArguments(
        _ cursor: inout AQLTokenCursor, delegate: inout some AQLParserDelegate,
        forOperation operation: String? = nil
    ) throws -> [any AQLExpression] {
        try withGrammar(&cursor, &delegate) { try $0.parseCallArguments(forOperation: operation) }
    }

    /// Parses a type name such as `String`, `ecore::EClass`, or `Sequence(EClass)`.
    ///
    /// - Parameter cursor: The tokens and position to read from.
    /// - Returns: The type as written, with qualification and element types.
    /// - Throws: ``AQLSyntaxError`` if the tokens do not start with a type name.
    public static func parseTypeName(_ cursor: inout AQLTokenCursor) throws -> String {
        var delegate = AQLDefaultParserDelegate()
        return try withGrammar(&cursor, &delegate) { try $0.parseTypeName() }
    }

    /// Parses a name made of segments separated by `::`, accepting keywords as segments.
    ///
    /// - Parameters:
    ///   - cursor: The tokens and position to read from.
    ///   - description: What the name denotes, for the error message.
    /// - Returns: The segments joined by `::`.
    /// - Throws: ``AQLSyntaxError`` if the tokens do not start with a name.
    public static func parseQualifiedName(
        _ cursor: inout AQLTokenCursor, describing description: String
    ) throws -> String {
        var delegate = AQLDefaultParserDelegate()
        return try withGrammar(&cursor, &delegate) { try $0.parseQualifiedName(describing: description) }
    }

    /// Parses one name, accepting a keyword as the name.
    ///
    /// - Parameters:
    ///   - cursor: The tokens and position to read from.
    ///   - description: What the name denotes, for the error message.
    /// - Returns: The name.
    /// - Throws: ``AQLSyntaxError`` if the current token is not a name.
    public static func parseNameSegment(
        _ cursor: inout AQLTokenCursor, describing description: String
    ) throws -> String {
        var delegate = AQLDefaultParserDelegate()
        return try withGrammar(&cursor, &delegate) { try $0.parseNameSegment(describing: description) }
    }

    /// Runs a grammar function over a cursor and delegate, writing both back afterwards.
    private static func withGrammar<Delegate: AQLParserDelegate, Result>(
        _ cursor: inout AQLTokenCursor, _ delegate: inout Delegate,
        _ body: (inout AQLGrammar<Delegate>) throws -> Result
    ) throws -> Result {
        var grammar = AQLGrammar(cursor: cursor, delegate: delegate)
        defer {
            cursor = grammar.cursor
            delegate = grammar.delegate
        }
        return try body(&grammar)
    }
}

// MARK: - Syntax highlighting

extension AQLSyntax {
    /// Splits AQL text into tokens for syntax highlighting.
    ///
    /// This never fails and does not parse. Comments are included, and text that is not valid
    /// AQL (unterminated strings, unknown characters) comes back as
    /// ``AQLTokenKind/invalid(_:)`` tokens, so every part of the text that is not blank is
    /// covered by exactly one token.
    ///
    /// - Parameter source: The AQL text.
    /// - Returns: The tokens in order, without an end-of-input token.
    public static func tokens(in source: String) -> [AQLToken] {
        AQLTokeniser.tokenise(source).tokens
    }
}
