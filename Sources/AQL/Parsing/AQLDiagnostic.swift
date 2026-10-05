//
//  AQLDiagnostic.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// How serious a diagnostic is.
public enum AQLDiagnosticSeverity: String, Sendable, Equatable, Hashable {
    /// The text is not valid AQL.
    case error

    /// The text is valid but probably not what was meant.
    case warning
}

/// The codes of the diagnostics that the AQL parser reports.
public enum AQLDiagnosticCode {
    /// A token appeared where the grammar does not allow it.
    public static let unexpectedToken = "aql.unexpectedToken"

    /// The text ended where more was required.
    public static let unexpectedEnd = "aql.unexpectedEnd"

    /// A string literal has no closing quote.
    public static let unterminatedString = "aql.unterminatedString"

    /// A `\u` escape in a string literal lacks four hexadecimal digits.
    public static let malformedEscape = "aql.malformedEscape"

    /// A number literal cannot be represented.
    public static let invalidNumber = "aql.invalidNumber"

    /// A character that AQL does not use.
    public static let invalidCharacter = "aql.invalidCharacter"

    /// Tokens remain after a complete expression.
    public static let trailingTokens = "aql.trailingTokens"
}

/// A problem found while tokenising or parsing AQL text.
public struct AQLDiagnostic: Sendable, Equatable, Hashable {
    /// How serious the problem is.
    public var severity: AQLDiagnosticSeverity

    /// The stable code of the problem, one of the ``AQLDiagnosticCode`` values.
    public var code: String

    /// A description of the problem for the user.
    public var message: String

    /// Where the problem is.
    public var span: AQLSourceSpan

    /// Creates a diagnostic.
    ///
    /// - Parameters:
    ///   - severity: How serious the problem is.
    ///   - code: The stable code of the problem.
    ///   - message: A description of the problem.
    ///   - span: Where the problem is.
    public init(
        severity: AQLDiagnosticSeverity = .error,
        code: String,
        message: String,
        span: AQLSourceSpan
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.span = span
    }

    /// The line of the problem, counting from 1.
    public var line: Int { span.line }

    /// The column of the problem, counting from 1.
    public var column: Int { span.column }

    /// The UTF-8 offset of the problem, counting from 0.
    public var offset: Int { span.offset }

    /// The number of UTF-8 code units the problem covers.
    public var length: Int { span.length }
}

/// The error thrown when AQL text does not follow the grammar.
public struct AQLSyntaxError: Error, Sendable, Equatable {
    /// The problem that stopped the parse.
    public let diagnostic: AQLDiagnostic

    /// Creates a syntax error.
    ///
    /// - Parameter diagnostic: The problem that stopped the parse.
    public init(_ diagnostic: AQLDiagnostic) {
        self.diagnostic = diagnostic
    }
}

extension AQLSyntaxError: CustomStringConvertible {
    /// The position and message of the problem.
    public var description: String {
        "Line \(diagnostic.line), column \(diagnostic.column): \(diagnostic.message)"
    }
}
