//
//  AQLCollectionExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Collection Operations

/// Represents collection operations in AQL (select, reject, collect, etc.).
///
/// Collection operations allow filtering, transformation, and querying of
/// collections in AQL expressions. These operations follow OCL semantics.
///
/// ## Supported Operations
///
/// ### Filtering
/// - `select(iterator | condition)` - Filter elements matching condition
/// - `reject(iterator | condition)` - Filter elements not matching condition
///
/// ### Transformation
/// - `collect(iterator | expression)` - Transform each element
///
/// ### Querying
/// - `any(iterator | condition)` - The first element matching the condition, or null
/// - `forAll(iterator | condition)` - True if all elements match
/// - `exists(iterator | condition)` - True if any element matches
///
/// ### Properties
/// - `size()` - Number of elements
/// - `isEmpty()` - True if collection is empty
/// - `notEmpty()` - True if collection is not empty
/// - `first()` - First element or null
/// - `last()` - Last element or null
///
/// ### Element Lookup
/// - `indexOf(element)` - 1-based index of first matching element, or 0 if not found
///   (0-based, -1 if absent, when ``AQLExecutionContext/usesOneBasedIndexOf`` is cleared)
///
/// ### Iteration
/// - `sortedBy(iterator | key)`, `one(iterator | condition)`, `isUnique(iterator | key)`,
///   `closure(iterator | next)`
///
/// ## Example Usage
///
/// ```swift
/// // Filter: persons->select(p | p.age > 18)
/// let adultsExpr = AQLCollectionExpression(
///     source: personsExpr,
///     operation: .select,
///     iterator: "p",
///     body: ageComparisonExpr
/// )
///
/// // Transform: persons->collect(p | p.name)
/// let namesExpr = AQLCollectionExpression(
///     source: personsExpr,
///     operation: .collect,
///     iterator: "p",
///     body: nameNavigationExpr
/// )
///
/// // Query: persons->size()
/// let sizeExpr = AQLCollectionExpression(
///     source: personsExpr,
///     operation: .size
/// )
/// ```
public struct AQLCollectionExpression: AQLExpression {
    /// Where the expression was written, if known.
    public let origin: SourceOrigin

    // MARK: - Types

    /// Collection operation type.
    public enum Operation: String, Sendable {
        // Filtering
        case select
        case reject

        // Transformation
        case collect

        // Querying
        case any
        case forAll
        case exists

        // Properties
        case size
        case isEmpty
        case notEmpty
        case first
        case last

        // Element lookup
        case indexOf

        // Iteration
        case sortedBy
        case one
        case isUnique
        case closure
    }

    // MARK: - Properties

    /// The source collection expression.
    public let source: any AQLExpression

    /// The operation to perform.
    public let operation: Operation

    /// Optional iterator variable name for operations that need it.
    ///
    /// Used by: select, reject, collect, any, forAll, exists
    public let iterator: String?

    /// Optional body expression evaluated for each element.
    ///
    /// Used by: select, reject, collect, any, forAll, exists
    public let body: (any AQLExpression)?

    // MARK: - Initialisation

    /// Creates a collection operation expression.
    ///
    /// - Parameters:
    ///   - source: The source collection expression
    ///   - operation: The operation to perform
    ///   - iterator: Optional iterator variable name
    ///   - body: Optional body expression
    ///   - origin: Where the expression was written, if known.
    public init(
        source: any AQLExpression,
        operation: Operation,
        iterator: String? = nil,
        body: (any AQLExpression)? = nil,
        origin: SourceOrigin = .init()
    ) {
        self.origin = origin
        self.source = source
        self.operation = operation
        self.iterator = iterator
        self.body = body
    }

    // MARK: - Evaluation

    /// Evaluates the operation by calling the collection service of the same name.
    ///
    /// A null source is treated as an empty collection by the operations that answer a
    /// question about it: `size` is 0, `isEmpty`, `forAll` and `isUnique` are true,
    /// `notEmpty`, `exists` and `one` are false, and `indexOf` reports that the element is
    /// absent. The remaining operations yield null.
    /// Operations with an iterator pass an ``AQLLambda`` built from ``iterator`` and ``body``;
    /// without an iterator, ``body`` is passed as an ordinary argument.
    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let sourceValue = try await source.evaluate(in: context)

        guard sourceValue != nil else {
            switch operation {
            case .size: return 0
            case .isEmpty, .forAll, .isUnique: return true
            case .notEmpty, .exists, .one: return false
            case .indexOf: return context.usesOneBasedIndexOf ? 0 : -1
            default: return nil
            }
        }

        var argument: [any AQLExpression] = []
        if let body {
            if let iterator {
                argument = [AQLLambdaExpression(iterator: iterator, body: body)]
            } else {
                argument = [body]
            }
        }
        return try await AQLCallExpression(
            source: AQLLiteralExpression(value: sourceValue), methodName: operation.rawValue,
            arguments: argument, usesArrow: true
        ).evaluate(in: context)
    }
}
