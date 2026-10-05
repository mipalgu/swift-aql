//
//  AQLLambda.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// An iterator expression such as `x | x.name` passed to an iteration service.
///
/// Lambdas are evaluated lazily by the service that receives them, once per
/// element, in a fresh variable scope that binds the iterator variable.
public struct AQLLambda: EcoreValue {
    /// The identity of this lambda (lambdas are compared by identity).
    public let id: UUID

    /// The iterator variable names.
    public let iterators: [String]

    /// The body expression.
    public let body: any AQLExpression

    /// Creates a lambda.
    ///
    /// - Parameters:
    ///   - iterators: The iterator variable names (usually one).
    ///   - body: The body expression.
    public init(iterators: [String], body: any AQLExpression) {
        self.id = UUID()
        self.iterators = iterators
        self.body = body
    }

    /// Evaluates the body with the iterator variables bound.
    ///
    /// - Parameters:
    ///   - values: The values to bind, matching ``iterators`` by position.
    ///   - context: The execution context.
    /// - Returns: The value of the body.
    /// - Throws: Any error raised by the body.
    @MainActor
    public func invoke(_ values: [any EcoreValue], in context: AQLExecutionContext) async throws
        -> (any EcoreValue)?
    {
        context.pushScope()
        defer { context.popScope() }
        for (name, value) in zip(iterators, values) { context.setVariable(name, value: value) }
        return try await body.evaluate(in: context)
    }

    /// Evaluates the body for a single element.
    ///
    /// - Parameters:
    ///   - value: The element bound to the first iterator.
    ///   - context: The execution context.
    /// - Returns: The value of the body.
    @MainActor
    public func invoke(_ value: any EcoreValue, in context: AQLExecutionContext) async throws
        -> (any EcoreValue)?
    {
        try await invoke([value], in: context)
    }

    public static func == (lhs: AQLLambda, rhs: AQLLambda) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// An expression that evaluates to an ``AQLLambda`` (an iterator argument).
///
/// Parsers build this node for the `x | body` argument of operations such as
/// `select`, `collect` or `sortedBy`.
public struct AQLLambdaExpression: AQLExpression {
    /// Where the expression was written, if known.
    public let origin: SourceOrigin

    /// The iterator variable names.
    public let iterators: [String]

    /// The body expression.
    public let body: any AQLExpression

    /// Creates a lambda expression.
    ///
    /// - Parameters:
    ///   - iterator: The iterator variable name.
    ///   - body: The body expression.
    ///   - origin: Where the expression was written, if known.
    public init(iterator: String, body: any AQLExpression, origin: SourceOrigin = .init()) {
        self.init(iterators: [iterator], body: body, origin: origin)
    }

    /// Creates a lambda expression with several iterator variables.
    ///
    /// - Parameters:
    ///   - iterators: The iterator variable names.
    ///   - body: The body expression.
    ///   - origin: Where the expression was written, if known.
    public init(iterators: [String], body: any AQLExpression, origin: SourceOrigin = .init()) {
        self.origin = origin
        self.iterators = iterators
        self.body = body
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        AQLLambda(iterators: iterators, body: body)
    }
}
