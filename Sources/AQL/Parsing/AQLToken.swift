//
//  AQLToken.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase

/// The kinds of token in AQL text.
///
/// The cases beyond the AQL grammar itself (brackets and ``other``) exist so that a host
/// language that embeds AQL expressions can present its own tokens to the parser.
public enum AQLTokenKind: Sendable, Equatable, Hashable {
    /// `(`
    case leftParen
    /// `)`
    case rightParen
    /// `,`
    case comma
    /// `:`
    case colon
    /// `::`
    case doubleColon
    /// `.`
    case dot
    /// `|`
    case pipe
    /// `?`
    case questionMark
    /// `{`
    case leftBrace
    /// `}`
    case rightBrace
    /// `[`, which AQL itself does not use
    case leftBracket
    /// `]`, which AQL itself does not use
    case rightBracket
    /// `/`, which divides unless the host says that it ends the expression
    case slash
    /// A reserved word, see ``AQLSyntax/keywords``.
    case keyword(String)
    /// A name.
    case identifier(String)
    /// A string literal with its escapes resolved.
    case stringLiteral(String)
    /// An integer literal.
    case integerLiteral(Int)
    /// A real literal.
    case realLiteral(Double)
    /// `true` or `false`.
    case booleanLiteral(Bool)
    /// An arithmetic, comparison, or arrow operator.
    case `operator`(String)
    /// A comment without its prefix, trimmed of surrounding blanks.
    case comment(String)
    /// Text that is not a valid token, as written.
    case invalid(String)
    /// A token of the host language that AQL does not interpret.
    case other
    /// The end of the text.
    case eof
}

extension AQLTokenKind: CustomStringConvertible {
    /// A description of the kind of token, for messages.
    public var description: String {
        switch self {
        case .leftParen: return "'('"
        case .rightParen: return "')'"
        case .comma: return "','"
        case .colon: return "':'"
        case .doubleColon: return "'::'"
        case .dot: return "'.'"
        case .pipe: return "'|'"
        case .questionMark: return "'?'"
        case .leftBrace: return "'{'"
        case .rightBrace: return "'}'"
        case .leftBracket: return "'['"
        case .rightBracket: return "']'"
        case .slash: return "'/'"
        case .keyword(let word): return "keyword '\(word)'"
        case .identifier(let name): return "name '\(name)'"
        case .stringLiteral: return "string literal"
        case .integerLiteral(let value): return "number \(value)"
        case .realLiteral(let value): return "number \(value)"
        case .booleanLiteral(let value): return "'\(value)'"
        case .operator(let text): return "'\(text)'"
        case .comment: return "comment"
        case .invalid(let text): return "invalid text '\(text)'"
        case .other: return "unexpected text"
        case .eof: return "end of input"
        }
    }
}

/// A token of AQL text with its position.
public struct AQLToken: Sendable, Equatable, Hashable {
    /// What the token is.
    public var kind: AQLTokenKind

    /// Where the token is.
    public var range: SourceRange

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - kind: What the token is.
    ///   - range: Where the token is.
    public init(kind: AQLTokenKind, range: SourceRange) {
        self.kind = kind
        self.range = range
    }

    /// Whether the token is a comment.
    public var isComment: Bool {
        if case .comment = kind { return true }
        return false
    }

    /// Whether the token is not valid AQL.
    public var isInvalid: Bool {
        if case .invalid = kind { return true }
        return false
    }
}

extension AQLTokenKind {
    /// The kind of highlighting token that corresponds to this kind of token.
    ///
    /// Collection type names such as `Sequence` are reported as type names. Tokens of a host
    /// language that AQL does not interpret are reported as plain text.
    public var highlightKind: SourceTokenKind {
        switch self {
        case .keyword: return .keyword
        case .identifier(let name):
            return AQLSyntax.collectionTypeNames.contains(name) ? .typeName : .identifier
        case .stringLiteral: return .string
        case .integerLiteral, .realLiteral: return .number
        case .booleanLiteral: return .boolean
        case .operator: return .operator
        case .comment: return .comment
        case .invalid: return .invalid
        case .other, .eof: return .text
        case .leftParen, .rightParen, .comma, .colon, .doubleColon, .dot, .pipe, .questionMark,
            .leftBrace, .rightBrace, .leftBracket, .rightBracket, .slash:
            return .punctuation
        }
    }
}

extension AQLToken {
    /// The token as a syntax highlighting token.
    public var sourceToken: SourceToken {
        SourceToken(kind: kind.highlightKind, range: range)
    }
}
