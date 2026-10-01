//
//  AQLTypeLiteralExpression.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// A type literal such as `ecore::EClass` or `String`.
///
/// Evaluates to an ``AQLTypeDescriptor`` that type-aware services such as
/// `filter`, `oclIsKindOf`, `eContents(Type)` and `allInstances` accept.
public struct AQLTypeLiteralExpression: AQLExpression {
    /// The package name, or nil for an unqualified type.
    public let packageName: String?

    /// The classifier name.
    public let typeName: String

    /// Creates a type literal.
    ///
    /// - Parameters:
    ///   - packageName: The package name, or nil.
    ///   - typeName: The classifier name.
    public init(packageName: String?, typeName: String) {
        self.packageName = packageName
        self.typeName = typeName
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        AQLTypeDescriptor(packageName: packageName, typeName: typeName)
    }
}
