//
//  AQLUnaryExpression.swift
//  AQL
//
//  Created by Rene Hexel on 15/02/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

// MARK: - Unary Operations

/// Represents unary operations in AQL (logical negation, numeric negation).
///
/// Unary expressions apply a single operator to one operand to produce a result.
///
/// ## Supported Operators
///
/// ### Logical
/// - `not` - Boolean negation
///
/// ### Arithmetic
/// - `-` - Numeric negation (unary minus)
///
/// ## Example Usage
///
/// ```swift
/// // Logical negation: not isActive
/// let notExpr = AQLUnaryExpression(
///     op: .not,
///     operand: isActiveExpr
/// )
///
/// // Numeric negation: -10
/// let negateExpr = AQLUnaryExpression(
///     op: .negate,
///     operand: AQLLiteralExpression(value: 10)
/// )
/// ```
public struct AQLUnaryExpression: AQLExpression {

    // MARK: - Types

    /// Unary operator type.
    public enum Operator: String, Sendable {
        /// Logical negation operator (not).
        case not = "not"

        /// Numeric negation operator (unary minus).
        case negate = "-"
    }

    // MARK: - Properties

    /// The operand expression.
    public let operand: any AQLExpression

    /// The operator to apply.
    public let op: Operator

    // MARK: - Initialisation

    /// Creates a unary expression.
    ///
    /// - Parameters:
    ///   - op: The operator
    ///   - operand: The operand
    public init(op: Operator, operand: any AQLExpression) {
        self.op = op
        self.operand = operand
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let value = try await operand.evaluate(in: context)

        switch op {
        case .not:
            return try evaluateNot(value)
        case .negate:
            return try evaluateNegate(value)
        }
    }

    // MARK: - Logical Operations

    /// Evaluates logical NOT.
    ///
    /// Returns the boolean negation of the operand.
    /// If the operand is not a boolean, returns nil.
    ///
    /// - Parameter value: The value to negate
    /// - Returns: The negated boolean value, or nil if not a boolean
    private func evaluateNot(_ value: (any EcoreValue)?) throws -> Bool? {
        guard let boolValue = value as? Bool else {
            return nil
        }
        return !boolValue
    }

    // MARK: - Arithmetic Operations

    /// Evaluates numeric negation (unary minus).
    ///
    /// Returns the numeric negation of the operand.
    /// Supports both integer and floating-point values.
    ///
    /// - Parameter value: The value to negate
    /// - Returns: The negated numeric value
    /// - Throws: AQLExecutionError.typeError if the operand is not numeric
    private func evaluateNegate(_ value: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let value = value else {
            return nil
        }

        if let intValue = value as? Int {
            return -intValue
        }

        if let doubleValue = value as? Double {
            return -doubleValue
        }

        throw AQLExecutionError.typeError("Cannot negate non-numeric value: \(type(of: value))")
    }
}
