//
//  AQLConditionalExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import EMFBase
import Foundation

// MARK: - Conditional Expression

/// Represents conditional expressions (if-then-else) in AQL.
///
/// Conditional expressions evaluate a condition and return one of two values
/// based on whether the condition is true or false.
///
/// ## Syntax
///
/// ```
/// if condition then thenExpression else elseExpression endif
/// ```
///
/// ## Example Usage
///
/// ```swift
/// // if age >= 18 then 'Adult' else 'Minor'
/// let conditional = AQLConditionalExpression(
///     condition: ageComparisonExpr,
///     thenExpression: AQLLiteralExpression(value: "Adult"),
///     elseExpression: AQLLiteralExpression(value: "Minor")
/// )
/// ```
///
/// ## Null Handling
///
/// If the condition evaluates to null or non-boolean, it is treated as false.
public struct AQLConditionalExpression: AQLExpression {

    // MARK: - Properties

    /// The condition expression (should evaluate to Boolean).
    public let condition: any AQLExpression

    /// The expression to evaluate if condition is true.
    public let thenExpression: any AQLExpression

    /// The expression to evaluate if condition is false or null.
    public let elseExpression: any AQLExpression

    // MARK: - Initialisation

    /// Creates a conditional expression.
    ///
    /// - Parameters:
    ///   - condition: The condition to test
    ///   - thenExpression: The true branch expression
    ///   - elseExpression: The false branch expression
    public init(
        condition: any AQLExpression,
        thenExpression: any AQLExpression,
        elseExpression: any AQLExpression
    ) {
        self.condition = condition
        self.thenExpression = thenExpression
        self.elseExpression = elseExpression
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate condition
        let conditionResult = try await condition.evaluate(in: context)

        // Check if condition is true
        if let boolValue = conditionResult as? Bool, boolValue {
            return try await thenExpression.evaluate(in: context)
        } else {
            return try await elseExpression.evaluate(in: context)
        }
    }
}
