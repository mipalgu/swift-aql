//
//  AQLExpression.swift
//  AQL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation

// MARK: - AQL Expression Protocol

/// Protocol for AQL expressions that can be evaluated within an execution context.
public protocol AQLExpression: Sendable {
    /// Evaluates the expression within the specified execution context.
    ///
    /// - Parameter context: The execution context providing model access and variable bindings
    /// - Returns: The result of evaluating the expression
    /// - Throws: AQLExecutionError if evaluation fails
    @MainActor
    func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)?
}

// MARK: - Variable Expression

/// Represents a variable reference in AQL.
///
/// AQL allows implicit 'self'. If the variable is not found in the context,
/// the context implementation may try to resolve it as a property of 'self'.
public struct AQLVariableExpression: AQLExpression {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        return try await context.getVariable(name)
    }
}

// MARK: - Navigation Expression

/// Represents property navigation (e.g., `object.property` or `object.reference`).
public struct AQLNavigationExpression: AQLExpression {
    public let source: any AQLExpression
    public let property: String

    /// If true, this is a null-safe navigation (AQL is generally forgiving).
    public let isNullSafe: Bool

    public init(source: any AQLExpression, property: String, isNullSafe: Bool = true) {
        self.source = source
        self.property = property
        self.isNullSafe = isNullSafe
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let sourceValue = try await source.evaluate(in: context)

        if sourceValue == nil {
            if isNullSafe {
                return nil
            } else {
                throw AQLExecutionError.typeError("Source for navigation '\(property)' is null")
            }
        }

        return try await context.navigate(from: sourceValue, property: property)
    }
}

// MARK: - Literal Expression

/// Represents a literal value (String, Integer, Boolean, Real, null).
public struct AQLLiteralExpression: AQLExpression {
    public let value: (any EcoreValue)?

    public init(value: (any EcoreValue)?) {
        self.value = value
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        return value
    }
}

// MARK: - String Interpolation Expression

/// Represents AQL string interpolation: `'some text ${expression} more text'`.
public struct AQLStringInterpolationExpression: AQLExpression {
    public struct Part: Sendable {
        let literal: String
        let expression: (any AQLExpression)?

        public init(literal: String, expression: (any AQLExpression)? = nil) {
            self.literal = literal
            self.expression = expression
        }
    }

    public let parts: [Part]

    public init(parts: [Part]) {
        self.parts = parts
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        var result = ""

        for part in parts {
            result += part.literal
            if let expr = part.expression {
                let val = try await expr.evaluate(in: context)
                if let val = val {
                    result += "\(val)"
                } else {
                    result += "null"
                }
            }
        }

        return result
    }
}
