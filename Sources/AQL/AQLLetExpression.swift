//
//  AQLLetExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

// MARK: - Let Expression

/// Represents let expressions for local variable bindings in AQL.
///
/// Let expressions allow defining local variables within an expression scope,
/// making complex expressions more readable and avoiding redundant computations.
///
/// ## Syntax
///
/// ```
/// let var1 = expr1, var2 = expr2 in bodyExpression
/// ```
///
/// ## Example Usage
///
/// ```swift
/// // let fullName = firstName + ' ' + lastName in fullName.toUpperCase()
/// let letExpr = AQLLetExpression(
///     bindings: [
///         ("fullName", AQLBinaryExpression(
///             left: firstNameExpr,
///             op: .add,
///             right: AQLBinaryExpression(
///                 left: AQLLiteralExpression(value: " "),
///                 op: .add,
///                 right: lastNameExpr
///             )
///         ))
///     ],
///     body: AQLCallExpression(
///         source: AQLVariableExpression(name: "fullName"),
///         methodName: "toUpperCase"
///     )
/// )
/// ```
///
/// ## Scoping
///
/// Variables defined in a let expression are only available within the body
/// expression. They shadow any outer variables with the same name.
public struct AQLLetExpression: AQLExpression {

    // MARK: - Properties

    /// Variable bindings: (name, init expression) pairs.
    public let bindings: [(String, any AQLExpression)]

    /// The body expression evaluated with the bound variables.
    public let body: any AQLExpression

    // MARK: - Initialisation

    /// Creates a let expression.
    ///
    /// - Parameters:
    ///   - bindings: The variable bindings
    ///   - body: The body expression
    public init(bindings: [(String, any AQLExpression)], body: any AQLExpression) {
        self.bindings = bindings
        self.body = body
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        // Push new scope
        context.pushScope()
        defer { context.popScope() }

        // Evaluate and bind variables
        for (name, initExpr) in bindings {
            let value = try await initExpr.evaluate(in: context)
            context.setVariable(name, value: value)
        }

        // Evaluate body
        return try await body.evaluate(in: context)
    }
}
