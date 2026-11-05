//
//  AQLBinaryExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import ECore
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
/// - `+` (add), `-` (subtract), `*` (multiply), `/` (divide), `mod` (modulo), `div` (integer division)
///
/// ### Comparison
/// - `=` (equals), `<>` (notEquals)
/// - `<` (lessThan), `>` (greaterThan), `<=` (lessOrEqual), `>=` (greaterOrEqual)
///
/// ### Logical
/// - `and`, `or`, `implies`, `xor`
///
/// ### String
/// - `+` (add) - If either operand is a string, the text of both operands joined, as in
///   `'times ' + 42` (`'times 42'`); a collection contributes the text of its elements
///   without separators, as in `'x' + Sequence{'a', 'b'}` (`'xab'`), unless the
///   ``AQLOptions/textForm`` of the context is ``AQLTextForm/bracketed``
///
/// ### Collection
/// - `+` (add) - Concatenation into a collection of the kind of the left operand, as
///   `concat` does: `Sequence{'a'} + Sequence{'a'}` is `Sequence{'a', 'a'}`, while
///   `OrderedSet{'a'} + Sequence{'a'}` is `OrderedSet{'a'}`
/// - `-` (sub) - The elements of the left operand that the right operand does not hold, in
///   a collection of the kind of the left operand: `Sequence{'a', 'b', 'a'} - Sequence{'a'}`
///   is `Sequence{'b'}`
///
/// Adding a collection to a value that is neither a collection nor a string, or subtracting
/// anything other than a collection from a collection, is a type error. A null operand of
/// `+` counts as empty text, so that `'x' + null` and `null + 'x'` are `'x'` and
/// `null + null` is `''`, unless the ``AQLOptions/nullAddition`` of the context is
/// ``AQLNullAddition/null``, which makes the result null. Any other arithmetic or comparison
/// operator with a null operand yields null.
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
    /// Where the expression was written, if known.
    public let origin: SourceOrigin

    // MARK: - Types

    /// Binary operator type.
    public enum Operator: String, Sendable {
        // Arithmetic
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"
        case mod = "mod"
        case div = "div"

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
    ///   - origin: Where the expression was written, if known.
    public init(left: any AQLExpression, op: Operator, right: any AQLExpression, origin: SourceOrigin = .init()) {
        self.origin = origin
        self.left = left
        self.op = op
        self.right = right
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        // Short-circuit evaluation for logical operators
        switch op {
        case .and:
            let leftValue = try await left.evaluate(in: context)
            if let leftBool = leftValue as? Bool, !leftBool {
                return false  // short-circuit: false and _ = false
            }
            let rightValue = try await right.evaluate(in: context)
            return evaluateAnd(leftValue, rightValue)
        case .or:
            let leftValue = try await left.evaluate(in: context)
            if let leftBool = leftValue as? Bool, leftBool {
                return true  // short-circuit: true or _ = true
            }
            let rightValue = try await right.evaluate(in: context)
            return evaluateOr(leftValue, rightValue)
        case .implies:
            let leftValue = try await left.evaluate(in: context)
            if let leftBool = leftValue as? Bool, !leftBool {
                return true  // short-circuit: false implies _ = true
            }
            let rightValue = try await right.evaluate(in: context)
            return evaluateImplies(leftValue, rightValue)
        default:
            // For all other operators, evaluate both operands eagerly
            let leftValue = try await left.evaluate(in: context)
            let rightValue = try await right.evaluate(in: context)
            switch op {
            case .xor:
                return evaluateXor(leftValue, rightValue)
            case .equals:
                return evaluateEquals(leftValue, rightValue)
            case .notEquals:
                return !evaluateEquals(leftValue, rightValue)
            case .add:
                return try Self.addition(leftValue, rightValue, in: context)
            default:
                // Arithmetic and comparison require non-null operands
                guard let leftValue = leftValue, let rightValue = rightValue else {
                    return nil
                }
                return try evaluateNonNull(leftValue, rightValue, in: context)
            }
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

        return AQLValues.areEqual(left, right)
    }

    // MARK: - Non-Null Operations

    /// Evaluates operations that require non-null operands.
    @MainActor
    private func evaluateNonNull(
        _ left: any EcoreValue, _ right: any EcoreValue, in context: AQLExecutionContext
    ) throws -> (any EcoreValue)? {
        switch op {
        case .add:
            return try Self.sum(left, right, in: context)
        case .subtract:
            return try Self.difference(left, right, in: context)
        case .multiply:
            return try evaluateMultiply(left, right)
        case .divide:
            return try evaluateDivide(left, right)
        case .mod:
            return try evaluateMod(left, right)
        case .div:
            return try evaluateDiv(left, right)
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

    /// The value of `left + right`, which the `add` services also compute.
    ///
    /// A null operand counts as empty text while the ``AQLOptions/nullAddition`` of the
    /// context is ``AQLNullAddition/emptyText``, so that the result is the text of the other
    /// operand; otherwise it makes the result null. Two operands that are not null combine
    /// as ``sum(_:_:in:)`` describes.
    ///
    /// - Parameters:
    ///   - left: The left operand.
    ///   - right: The right operand.
    ///   - context: The context whose options apply.
    /// - Returns: The sum, concatenated text or concatenated collection, or null.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` for operands that cannot be added.
    @MainActor
    static func addition(
        _ left: (any EcoreValue)?, _ right: (any EcoreValue)?, in context: AQLExecutionContext
    ) throws -> (any EcoreValue)? {
        guard let left, let right else {
            guard context.options.nullAddition == .emptyText else { return nil }
            let emptyText: any EcoreValue = ""
            return try sum(left ?? emptyText, right ?? emptyText, in: context)
        }
        return try sum(left, right, in: context)
    }

    /// The value of `left + right` for operands that are not null.
    ///
    /// If either operand is a string, the result is the text of the left operand followed by
    /// that of the right one, in the ``AQLOptions/textForm`` of the context. Otherwise two
    /// collections are concatenated into a collection of the kind of the left operand, so
    /// that an ordered set or a set leaves out elements it already holds, and two numbers
    /// are added.
    ///
    /// - Parameters:
    ///   - left: The left operand.
    ///   - right: The right operand.
    ///   - context: The context whose options shape the result.
    /// - Returns: The sum, concatenated text or concatenated collection.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` for any other combination of operands.
    @MainActor
    private static func sum(
        _ left: any EcoreValue, _ right: any EcoreValue, in context: AQLExecutionContext
    ) throws -> any EcoreValue {
        if left is String || right is String {
            let form = context.options.textForm
            return form.text(of: left) + form.text(of: right)
        }
        if let leftItems = AQLValues.elements(of: left), let rightItems = AQLValues.elements(of: right) {
            return context.collection(leftItems + rightItems, kind: context.collectionKind(of: left))
        }

        // Numeric addition
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt + rightInt
        }

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
            return leftDouble + rightDouble
        }

        throw AQLExecutionError.typeError("Cannot add \(type(of: left)) and \(type(of: right))")
    }

    /// The value of `left - right`.
    ///
    /// For two collections, the result holds the elements of the left operand that the right
    /// operand does not hold, every occurrence of them included, in a collection of the kind
    /// of the left operand. Two numbers are subtracted.
    ///
    /// - Parameters:
    ///   - left: The left operand.
    ///   - right: The right operand.
    ///   - context: The context whose options shape a collection result.
    /// - Returns: The difference.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` for any other combination of operands.
    @MainActor
    static func difference(
        _ left: any EcoreValue, _ right: any EcoreValue, in context: AQLExecutionContext
    ) throws -> any EcoreValue {
        if let leftItems = AQLValues.elements(of: left), let rightItems = AQLValues.elements(of: right) {
            let remaining = leftItems.filter { item in !rightItems.contains { AQLValues.areEqual($0, item) } }
            return context.collection(remaining, kind: context.collectionKind(of: left))
        }
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt - rightInt
        }

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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

    private func evaluateDiv(_ left: any EcoreValue, _ right: any EcoreValue) throws -> (
        any EcoreValue
    ) {
        if let leftInt = AQLValues.integer(left), let rightInt = AQLValues.integer(right) {
            guard rightInt != 0 else {
                throw AQLExecutionError.invalidOperation("Division by zero")
            }
            return leftInt / rightInt
        }

        throw AQLExecutionError.typeError(
            "Cannot perform integer division on \(type(of: left)) and \(type(of: right))")
    }

    // MARK: - Comparison Operations

    private func evaluateLessThan(_ left: any EcoreValue, _ right: any EcoreValue) throws -> Bool {
        if let leftInt = left as? Int, let rightInt = right as? Int {
            return leftInt < rightInt
        }

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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

        if let leftDouble = Self.asDouble(left), let rightDouble = Self.asDouble(right) {
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
    private static func asDouble(_ value: any EcoreValue) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        return nil
    }
}
