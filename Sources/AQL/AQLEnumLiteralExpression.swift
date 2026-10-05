//
//  AQLEnumLiteralExpression.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// An enumeration literal such as `genmodel::GenDelegationKind::None`.
///
/// Enumeration attributes hold the literal name as a `String` (this is how the
/// XMI loader stores them), so the expression evaluates to that name and
/// compares equal to attribute values.
public struct AQLEnumLiteralExpression: AQLExpression {
    /// Where the expression was written, if known.
    public let origin: SourceOrigin

    /// The package name.
    public let packageName: String?

    /// The enumeration name.
    public let enumName: String

    /// The literal name.
    public let literal: String

    /// Creates an enumeration literal.
    ///
    /// - Parameters:
    ///   - packageName: The package name, or nil.
    ///   - enumName: The enumeration name.
    ///   - literal: The literal name.
    ///   - origin: Where the expression was written, if known.
    public init(packageName: String?, enumName: String, literal: String, origin: SourceOrigin = .init()) {
        self.origin = origin
        self.packageName = packageName
        self.enumName = enumName
        self.literal = literal
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        literal
    }
}
