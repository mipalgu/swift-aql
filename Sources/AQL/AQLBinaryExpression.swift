//
//  AQLBinaryExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

// MARK: - Binary Operations

/// Represents binary operations in AQL (arithmetic, comparison, logical).
///
/// Binary expressions combine two operands with an operator to produce a result.
/// Operators follow standard mathematical and logical semantics.
///
/// ## Supported Operators
///
/// ### Arithmetic
/// - `+` (add), `-` (subtract), `*` (multiply), `/` (divide), `mod` (modulo)
///
/// ### Comparison
/// - `=` (equals), `<>` (notEquals)
/// - `<` (lessThan), `>` (greaterThan), `<=` (lessOrEqual), `>=` (greaterOrEqual)
///
/// ### Logical
/// - `and`, `or`, `implies`, `xor`
///
/// ### String
/// - `+` (concat) - String concatenation
///
/// ## Example Usage
///
/// ```swift
/// // Arithmetic: age + 10
/// let addExpr = AQLBinaryExpression(
///     left: ageExpr,
///     op: .add,
///     right: AQLLiteralExpression(value: 10)
/// )
///
/// // Comparison: age > 18
/// let comparisonExpr = AQLBinaryExpression(
///     left: ageExpr,
///     op: .greaterThan,
///     right: AQLLiteralExpression(value: 18)
/// )
///
/// // Logical: isActive and isPublic
/// let logicalExpr = AQLBinaryExpression(
///     left: isActiveExpr,
///     op: .and,
///     right: isPublicExpr
/// )
/// ```
public struct AQLBinaryExpression: AQLExpression {

    // MARK: - Types

    /// Binary operator type.
    public enum Operator: String, Sendable {
        // Arithmetic
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        case mod = "mod"

        // Comparison
        case equals = "="
        case notEquals = "<>"
        case lessThan = "<"
        case greaterThan = ">"
        case lessOrEqual = "<="
        case greaterOrEqual = ">="

        // Logical
        case and = "and"
        case or = "or"
        case implies = "implies"
        case xor = "xor"
    }

    // MARK: - Properties

    /// The left operand expression.
    public let left: any AQLExpression

    /// The right operand expression.
    public let right: any AQLExpression

    /// The operator to apply.
    public let op: Operator

    // MARK: - Initialisation

    /// Creates a binary expression.
    ///
    /// - Parameters:
    ///   - left: The left operand
    ///   - op: The operator
    ///   - right: The right operand
    public init(left: any AQLExpression, op: Operator, right: any AQLExpression) {
        self.left = left
        self.op = op
        self.right = right
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate operands
        let leftValue = try await left.evaluate(in: context)
        let rightValue = try await right.evaluate(in: context)

        // Handle null operands based on operator type
        switch op {
        case .and:
            return evaluateAnd(leftValue, rightValue)
        case .or:
            return evaluateOr(leftValue, rightValue)
        case .implies:
            return evaluateImplies(leftValue, rightValue)
        case .xor:
            return evaluateXor(leftValue, rightValue)
        case .equals:
            return evaluateEquals(leftValue, rightValue)
        case .notEquals:
            return !evaluateEquals(leftValue, rightValue)
        default:
            // Arithmetic and comparison require non-null operands
            guard let leftValue = leftValue, let rightValue = rightValue else {
                return nil
            }
            return try evaluateNonNull(leftValue, rightValue)
        }
    }

    // MARK: - Logical Operations

    /// Evaluates logical AND with three-valued logic.
    ///
    /// Truth table:
    /// - true && true = true
    /// - true && false = false
    /// - true && null = null
    /// - false && _ = false
    /// - null && false = false
    /// - null && true = null
    /// - null && null = null
    private func evaluateAnd(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool? {
        let leftBool = left as? Bool
        let rightBool = right as? Bool

        // false && _ = false
        if let l = leftBool, !l {
            return false
        }

        // _ && false = false
        if let r = rightBool, !r {
            return false
        }

        // true && true = true
        if let l = leftBool, let r = rightBool, l && r {
            return true
        }

        // Otherwise null
        return nil
    }

    /// Evaluates logical OR with three-valued logic.
    private func evaluateOr(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool? {
        let leftBool = left as? Bool
        let rightBool = right as? Bool

        // true || _ = true
        if let l = leftBool, l {
            return true
        }

        // _ || true = true
        if let r = rightBool, r {
            return true
        }

        // false || false = false
        if let l = leftBool, let r = rightBool, !l && !r {
            return false
        }

        // Otherwise null
        return nil
    }

    /// Evaluates logical IMPLIES with three-valued logic.
    ///
    /// Truth table:
    /// - false implies _ = true
    /// - true implies true = true
    /// - true implies false = false
    /// - true implies null = null
    /// - null implies true = true
    /// - null implies _ = null
    private func evaluateImplies(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool? {
        let leftBool = left as? Bool
        let rightBool = right as? Bool

        // false implies _ = true
        if let l = leftBool, !l {
            return true
        }

        // _ implies true = true
        if let r = rightBool, r {
            return true
        }

        // true implies false = false
        if let l = leftBool, let r = rightBool, l && !r {
            return false
        }

        // Otherwise null
        return nil
    }

    /// Evaluates logical XOR.
    private func evaluateXor(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool? {
        guard let leftBool = left as? Bool, let rightBool = right as? Bool else {
            return nil
        }

        return leftBool != rightBool
    }

    // MARK: - Equality

    /// Evaluates equality comparison.
    private func evaluateEquals(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool {
        // Null handling
        if left == nil && right == nil {
            return true
        }
        if left == nil || right == nil {
            return false
        }

        // Compare values
        // Use String representation as a fallback comparison
        return String(describing: left!) == String(describing: right!)
    }

    // MARK: - Non-Null Operations

    /// Evaluates operations that require non-null operands.
    private func evaluateNonNull(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    )? {
        switch op {
        case .add:
            return try evaluateAdd(left, right)
        case .subtract:
            return try evaluateSubtract(left, right)
        case .multiply:
            return try evaluateMultiply(left, right)
        case .divide:
            return try evaluateDivide(left, right)
        case .mod:
            return try evaluateMod(left, right)
        case .lessThan:
            return try evaluateLessThan(left, right)
        case .greaterThan:
            return try evaluateGreaterThan(left, right)
        case .lessOrEqual:
            return try evaluateLessOrEqual(left, right)
        case .greaterOrEqual:
            return try evaluateGreaterOrEqual(left, right)
        default:
            throw AQLExecutionError.invalidOperation("Unsupported operator: \(op.rawValue)")
        }
    }

    // MARK: - Arithmetic Operations

    /// Addition or string concatenation.
    private func evaluateAdd(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    ) {
        // String concatenation
        if let leftStr = left as? String, let rightStr = right as? String {
            return leftStr + rightStr
        }

        // Numeric addition
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt + rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble + rightDouble
        }

        throw AQLExecutionError.typeError("Cannot add \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateSubtract(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    ) {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt - rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble - rightDouble
        }

        throw AQLExecutionError.typeError(
            "Cannot subtract \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateMultiply(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    ) {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt * rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble * rightDouble
        }

        throw AQLExecutionError.typeError(
            "Cannot multiply \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateDivide(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    ) {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            guard rightInt != 0 else {
                throw AQLExecutionError.invalidOperation("Division by zero")
            }
            return leftInt / rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            guard rightDouble != 0 else {
                throw AQLExecutionError.invalidOperation("Division by zero")
            }
            return leftDouble / rightDouble
        }

        throw AQLExecutionError.typeError("Cannot divide \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateMod(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    ) {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            guard rightInt != 0 else {
                throw AQLExecutionError.invalidOperation("Modulo by zero")
            }
            return leftInt % rightInt
        }

        throw AQLExecutionError.typeError(
            "Cannot perform modulo on \(type(of: left)) and \(type(of: right))")
    }

    // MARK: - Comparison Operations

    private func evaluateLessThan(_ left: any EcoreValue, _ right: any EcoreValue) throws -> Bool {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt < rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble < rightDouble
        }

        if let leftStr = left as? String, let rightStr = right as? String {
            return leftStr < rightStr
        }

        throw AQLExecutionError.typeError(
            "Cannot compare \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateGreaterThan(_ left: any EcoreValue, _ right: any EcoreValue) throws -> Bool
    {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt > rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble > rightDouble
        }

        if let leftStr = left as? String, let rightStr = right as? String {
            return leftStr > rightStr
        }

        throw AQLExecutionError.typeError(
            "Cannot compare \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateLessOrEqual(_ left: any EcoreValue, _ right: any EcoreValue) throws -> Bool
    {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt <= rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble <= rightDouble
        }

        if let leftStr = left as? String, let rightStr = right as? String {
            return leftStr <= rightStr
        }

        throw AQLExecutionError.typeError(
            "Cannot compare \(type(of: left)) and \(type(of: right))")
    }

    private func evaluateGreaterOrEqual(_ left: any EcoreValue, _ right: any EcoreValue) throws
        -> Bool
    {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt >= rightInt
        }

        if let leftDouble = asDouble(left), let rightDouble = asDouble(right) {
            return leftDouble >= rightDouble
        }

        if let leftStr = left as? String, let rightStr = right as? String {
            return leftStr >= rightStr
        }

        throw AQLExecutionError.typeError(
            "Cannot compare \(type(of: left)) and \(type(of: right))")
    }

    // MARK: - Helpers

    /// Attempts to convert a value to Double.
    private func asDouble(_ value: any EcoreValue) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        return nil
    }
}
