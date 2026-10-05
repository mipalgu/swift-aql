//
//  AQLParserDelegate.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase

/// The hooks through which a host language shapes the expressions that ``AQLParser`` builds.
///
/// Both hooks have default implementations, so a host adopts only the one it needs. A host
/// that embeds AQL in a template language typically builds its own call node (so that calls
/// can resolve to templates and queries before the AQL library) and recognises extra
/// primary expressions of its own.
public protocol AQLParserDelegate {
    /// Builds the node for a call.
    ///
    /// The parser calls this for `receiver.name(arguments)` and for a bare `name(arguments)`.
    /// For a bare call the receiver is the implicit `self` where the grammar says so (inside
    /// iterator bodies, and for the OCL type operations) and `nil` otherwise.
    ///
    /// The default builds an ``AQLCallExpression``.
    ///
    /// - Parameters:
    ///   - name: The name of the operation.
    ///   - receiver: The receiver, if any.
    ///   - arguments: The argument expressions.
    ///   - origin: Where the call was written.
    /// - Returns: The node for the call.
    mutating func makeCall(
        name: String, receiver: (any AQLExpression)?, arguments: [any AQLExpression],
        origin: SourceOrigin
    ) -> any AQLExpression

    /// Offers the host the chance to parse a primary expression that starts with a name.
    ///
    /// The parser calls this when the current token is the identifier or keyword `name`, before
    /// it treats the name as a variable, qualified name, call, or collection literal. A host
    /// that recognises the construct consumes its tokens from the cursor (it may parse nested
    /// expressions with ``AQLParser/parseExpression(_:delegate:)``) and returns the node. A host
    /// that does not recognise it returns `nil` and consumes nothing.
    ///
    /// The default returns `nil`.
    ///
    /// - Parameters:
    ///   - name: The text of the current identifier or keyword token.
    ///   - cursor: The cursor, positioned on the name token.
    /// - Returns: The node, or `nil` if the host does not handle the name.
    /// - Throws: ``AQLSyntaxError`` if the construct is malformed.
    mutating func parsePrimary(named name: String, cursor: inout AQLTokenCursor) throws
        -> (any AQLExpression)?
}

extension AQLParserDelegate {
    /// Builds an ``AQLCallExpression``.
    public mutating func makeCall(
        name: String, receiver: (any AQLExpression)?, arguments: [any AQLExpression],
        origin: SourceOrigin
    ) -> any AQLExpression {
        AQLCallExpression(source: receiver, methodName: name, arguments: arguments, origin: origin)
    }

    /// Declines every name.
    public mutating func parsePrimary(named name: String, cursor: inout AQLTokenCursor) throws
        -> (any AQLExpression)?
    {
        nil
    }
}

/// The delegate that builds plain AQL nodes and adds no primary expressions.
public struct AQLDefaultParserDelegate: AQLParserDelegate {
    /// Creates the default delegate.
    public init() {}
}
