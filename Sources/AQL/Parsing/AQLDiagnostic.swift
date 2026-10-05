//
//  AQLDiagnostic.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase

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

/// The error thrown when AQL text does not follow the grammar.
public struct AQLSyntaxError: Error, Sendable, Equatable {
    /// The problem that stopped the parse.
    public let diagnostic: SourceDiagnostic

    /// Creates a syntax error.
    ///
    /// - Parameter diagnostic: The problem that stopped the parse.
    public init(_ diagnostic: SourceDiagnostic) {
        self.diagnostic = diagnostic
    }
}

extension AQLSyntaxError: CustomStringConvertible {
    /// The position and message of the problem.
    public var description: String {
        let start = diagnostic.range?.start ?? .start
        return "Line \(start.line), column \(start.column): \(diagnostic.message)"
    }
}
