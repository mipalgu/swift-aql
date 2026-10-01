//
//  AQLCallExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Method Call Expression

/// Represents method/operation calls in AQL.
///
/// Call expressions invoke operations on objects or call standalone functions.
/// This includes OCL standard library operations, custom queries, and services.
///
/// ## Call Types
///
/// ### Object Operations
/// ```swift
/// // obj.toString()
/// AQLCallExpression(
///     source: objExpr,
///     methodName: "toString",
///     arguments: []
/// )
/// ```
///
/// ### Standalone Functions
/// ```swift
/// // max(value1, value2)
/// AQLCallExpression(
///     source: nil,
///     methodName: "max",
///     arguments: [value1Expr, value2Expr]
/// )
/// ```
///
/// ## Dispatch
///
/// A call `receiver.name(args)` (or `receiver->name(args)` when ``usesArrow`` is set) looks up a
/// service by name, receiver kind and argument count: first among the services registered on the
/// execution context (latest registration first), then in the standard library. A call without a
/// receiver first looks for a standalone service and otherwise treats its first argument as the
/// receiver, so `min(a, b)` and `a.min(b)` are equivalent. When no service matches and the receiver
/// is an object, a zero-argument call falls back to navigating the structural feature of that name.
///
/// ## Iterator arguments
///
/// Operations such as `select` take an ``AQLLambdaExpression`` argument. Arguments of services that
/// accept type arguments may be bare identifiers or ``AQLTypeLiteralExpression`` nodes.
public struct AQLCallExpression: AQLExpression {

    // MARK: - Properties

    /// Optional source object expression (nil for standalone functions).
    public let source: (any AQLExpression)?

    /// The method/function name to invoke.
    public let methodName: String

    /// Argument expressions passed to the method.
    public let arguments: [any AQLExpression]

    /// Whether the call was written with `->`.
    ///
    /// The receiver of an arrow call is coerced to a collection: null becomes an empty collection
    /// and any other non-collection value becomes a single-element collection.
    public let usesArrow: Bool

    // MARK: - Initialisation

    /// Creates a method call expression.
    ///
    /// - Parameters:
    ///   - source: Optional source object (nil for standalone functions)
    ///   - methodName: The method name
    ///   - arguments: The argument expressions
    ///   - usesArrow: Whether the call was written with `->`
    public init(
        source: (any AQLExpression)? = nil,
        methodName: String,
        arguments: [any AQLExpression] = [],
        usesArrow: Bool = false
    ) {
        self.source = source
        self.methodName = methodName
        self.arguments = arguments
        self.usesArrow = usesArrow
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        var receiver = try await source?.evaluate(in: context)
        var hasReceiver = source != nil
        var argumentExpressions = arguments

        if hasReceiver && usesArrow {
            receiver = AQLValues.collection(AQLValues.coerceToCollection(receiver))
        }

        if !hasReceiver,
            context.services.find(
                name: methodName, receiver: nil, hasReceiver: false,
                argumentCount: argumentExpressions.count) == nil,
            let first = argumentExpressions.first
        {
            receiver = try await first.evaluate(in: context)
            argumentExpressions.removeFirst()
            hasReceiver = true
        }

        guard
            let service = context.services.find(
                name: methodName, receiver: receiver, hasReceiver: hasReceiver,
                argumentCount: argumentExpressions.count)
        else {
            return try await fallback(receiver: receiver, argumentCount: argumentExpressions.count, in: context)
        }

        var argumentValues: [(any EcoreValue)?] = []
        for expression in argumentExpressions {
            if service.acceptsTypeArguments, let type = try await typeArgument(expression, in: context) {
                argumentValues.append(type)
            } else {
                argumentValues.append(try await expression.evaluate(in: context))
            }
        }

        return try await service.implementation(
            AQLServiceCall(
                name: methodName, receiver: receiver, arguments: argumentValues, context: context))
    }

    /// Resolves an argument written as a bare identifier to a type descriptor.
    @MainActor
    private func typeArgument(_ expression: any AQLExpression, in context: AQLExecutionContext)
        async throws -> (any EcoreValue)?
    {
        guard let variable = expression as? AQLVariableExpression else { return nil }
        if let bound = try? await context.getVariable(variable.name),
            AQLTypeDescriptor(value: bound) != nil
        {
            return bound
        }
        return AQLTypeDescriptor(qualifiedName: variable.name)
    }

    /// Handles calls for which no service exists.
    @MainActor
    private func fallback(
        receiver: (any EcoreValue)?, argumentCount: Int, in context: AQLExecutionContext
    ) async throws -> (any EcoreValue)? {
        if receiver is any EObject {
            if argumentCount == 0, let value = try? await context.navigate(from: receiver, property: methodName) {
                return value
            }
            // TODO: Delegate to execution engine for EOperation invocation
            throw AQLExecutionError.invalidOperation(
                "EOperation invocation not yet implemented for '\(methodName)'")
        }
        throw AQLExecutionError.invalidOperation("Unknown method: \(methodName)")
    }
}
