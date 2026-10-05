//
//  AQLTokenCursor.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// A position in a sequence of tokens, together with the context the expression grammar keeps.
///
/// A host that embeds AQL expressions in its own syntax creates a cursor over its tokens
/// (converted to ``AQLToken`` values), positions it at the start of an expression, calls
/// ``AQLParser/parseExpression(_:delegate:)``, and continues from the position the cursor
/// ends at.
public struct AQLTokenCursor: Sendable {
    /// The decision of a host about whether a token ends the expression.
    ///
    /// The closure receives the current token and the one after it. It is consulted where the
    /// grammar could take the token as part of the expression, which today is the `/` that
    /// divides: a host whose directives end in `/]` answers `true` for a slash followed by `]`.
    public typealias Terminator = @Sendable (_ token: AQLToken, _ next: AQLToken?) -> Bool

    /// The tokens being read.
    public let tokens: [AQLToken]

    /// The index of the current token.
    public var position: Int

    /// How many iterator bodies or postconditions enclose the expression being parsed.
    ///
    /// Inside them, calls without a receiver apply to the implicit `self`.
    public var implicitReceiverDepth: Int

    /// How many argument lists of type operations enclose the expression being parsed.
    ///
    /// Inside them, qualified names denote types.
    public var typeArgumentDepth: Int = 0

    /// Whether a token ends the expression, as decided by the host.
    private let terminator: Terminator

    /// Creates a cursor.
    ///
    /// - Parameters:
    ///   - tokens: The tokens to read, without comments.
    ///   - position: The index of the first token to read (default: 0).
    ///   - implicitReceiverDepth: The number of enclosing implicit receiver contexts (default: 0).
    ///   - terminator: Decides whether a token ends the expression (default: no token does).
    public init(
        tokens: [AQLToken],
        position: Int = 0,
        implicitReceiverDepth: Int = 0,
        terminator: @escaping Terminator = { _, _ in false }
    ) {
        self.tokens = tokens
        self.position = position
        self.implicitReceiverDepth = implicitReceiverDepth
        self.terminator = terminator
    }

    /// The current token, or `nil` after the last.
    public var current: AQLToken? {
        position >= 0 && position < tokens.count ? tokens[position] : nil
    }

    /// The kind of the current token, or ``AQLTokenKind/eof`` after the last.
    public var currentKind: AQLTokenKind { current?.kind ?? .eof }

    /// The token the given number of places after the current one.
    ///
    /// - Parameter offset: How many tokens to look ahead (default: 1).
    /// - Returns: The token, or `nil` if there is none.
    public func peek(_ offset: Int = 1) -> AQLToken? {
        let index = position + offset
        return index >= 0 && index < tokens.count ? tokens[index] : nil
    }

    /// The kind of the token the given number of places after the current one.
    ///
    /// - Parameter offset: How many tokens to look ahead (default: 1).
    /// - Returns: The kind, or `nil` if there is no such token.
    public func peekKind(_ offset: Int = 1) -> AQLTokenKind? { peek(offset)?.kind }

    /// Moves to the next token.
    public mutating func advance() {
        position += 1
    }

    /// Whether the host says that the current token ends the expression.
    public var atTerminator: Bool {
        guard let token = current else { return true }
        return terminator(token, peek())
    }

    /// The position at which a problem at the current token is reported.
    var errorSpan: AQLSourceSpan {
        current?.span ?? tokens.last?.span ?? AQLSourceSpan(line: 1, column: 1)
    }

    /// Builds the error for a problem at the current token.
    ///
    /// The error is reported as ``AQLDiagnosticCode/unexpectedEnd`` when the current token is
    /// the end of the input.
    ///
    /// - Parameters:
    ///   - message: What is wrong.
    ///   - code: The diagnostic code (default: ``AQLDiagnosticCode/unexpectedToken``).
    /// - Returns: The error, positioned at the current token.
    public func syntaxError(
        _ message: String, code: String = AQLDiagnosticCode.unexpectedToken
    ) -> AQLSyntaxError {
        AQLSyntaxError(
            AQLDiagnostic(
                code: currentKind == .eof ? AQLDiagnosticCode.unexpectedEnd : code,
                message: message, span: errorSpan))
    }

    /// Consumes a token of the given kind.
    ///
    /// - Parameter kind: The kind of token that must be current.
    /// - Throws: ``AQLSyntaxError`` at the current token if it is of another kind.
    public mutating func expect(_ kind: AQLTokenKind) throws {
        guard currentKind == kind else {
            throw syntaxError("Expected \(kind) but found \(currentKind)")
        }
        advance()
    }
}
