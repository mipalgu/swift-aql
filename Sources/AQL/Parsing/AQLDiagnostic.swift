//
//  AQLDiagnostic.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase

/// The codes of the diagnostics that the AQL parser and the evaluation of expressions report.
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

    /// A dot call on a collection reached an element without the service, which the
    /// collection itself has.
    ///
    /// While ``AQLOptions/dotCalls`` is ``AQLDotCalls/eachElement``, a dot call such as
    /// `Sequence{1, 2}.size()` is made on each element, as Eclipse AQL does, rather than on
    /// the collection, as version 0.6 does. When an element has no service of the name but the
    /// collection has one, the call most likely meant the collection's service, written
    /// `Sequence{1, 2}->size()`. Evaluation reports this code as a warning in
    /// ``AQLExecutionContext/diagnostics``.
    public static let dotCallOnElements = "aql.dotCallOnElements"

    /// A navigation over a collection left out elements that have no feature of the name.
    ///
    /// While ``AQLOptions/dotCalls`` is ``AQLDotCalls/eachElement``, a navigation such as
    /// `self.items.genre` navigates the feature from each element of the collection and leaves
    /// out an element without it, as Eclipse AQL does. Evaluation then reports this code as a
    /// warning in ``AQLExecutionContext/diagnostics``, once for each type of element left out,
    /// with a message such as `Feature genre not found in EClass Periodical`.
    public static let featureNotFound = "aql.featureNotFound"

    /// A dot call on a collection left out elements that have no service of the name for
    /// arguments of their types.
    ///
    /// While ``AQLOptions/dotCalls`` is ``AQLDotCalls/eachElement``, a dot call such as
    /// `Sequence{'a', 1}.toUpper()` is made on each element of the collection and leaves out an
    /// element without such a service, as Eclipse AQL does. Evaluation then reports this code
    /// as a warning in ``AQLExecutionContext/diagnostics``, once for each type of element left
    /// out, with a message such as `Couldn't find the 'toUpper(Integer)' service`. The
    /// signature in the message lists the type of the element followed by the types of the
    /// arguments, with `?` for an argument that was not evaluated. When the collection itself
    /// has a service of the name, the warning is ``dotCallOnElements`` instead.
    public static let serviceNotFound = "aql.serviceNotFound"
}

/// The messages of the diagnostics that the evaluation of expressions reports.
enum AQLDiagnosticMessage {
    /// The separator between the types in a service signature.
    static let signatureSeparator = ","

    /// The placeholder for the type of an argument that was not evaluated.
    static let unevaluatedArgument = "?"

    /// The message of a warning with the code ``AQLDiagnosticCode/featureNotFound``.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - type: The type of the element without the feature.
    /// - Returns: The message.
    static func featureNotFound(_ feature: String, in type: AQLValueType) -> String {
        guard type.isObject else {
            return "Attempt to access feature (\(feature)) on a value that is not a model object (\(type.name))"
        }
        return "Feature \(feature) not found in EClass \(type.name)"
    }

    /// The message of a warning with the code ``AQLDiagnosticCode/serviceNotFound``.
    ///
    /// - Parameters:
    ///   - service: The name of the service.
    ///   - type: The type of the element without the service.
    ///   - argumentTypes: The types of the arguments, `nil` for those not evaluated.
    /// - Returns: The message.
    static func serviceNotFound(_ service: String, for type: AQLValueType, argumentTypes: [AQLValueType?]) -> String {
        let types = [type.name] + argumentTypes.map { $0?.name ?? unevaluatedArgument }
        return "Couldn't find the '\(service)(\(types.joined(separator: signatureSeparator)))' service"
    }
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
