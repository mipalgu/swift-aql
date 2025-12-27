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
/// - `any(iterator | condition)` - True if any element matches
/// - `forAll(iterator | condition)` - True if all elements match
/// - `exists(iterator | condition)` - True if any element matches (alias for any)
///
/// ### Properties
/// - `size()` - Number of elements
/// - `isEmpty()` - True if collection is empty
/// - `notEmpty()` - True if collection is not empty
/// - `first()` - First element or null
/// - `last()` - Last element or null
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
    public init(
        source: any AQLExpression,
        operation: Operation,
        iterator: String? = nil,
        body: (any AQLExpression)? = nil
    ) {
        self.source = source
        self.operation = operation
        self.iterator = iterator
        self.body = body
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate source
        let sourceValue = try await source.evaluate(in: context)

        // Handle null source
        guard let sourceValue = sourceValue else {
            // Most operations on null return null or empty
            switch operation {
            case .size:
                return 0
            case .isEmpty:
                return true
            case .notEmpty:
                return false
            case .first, .last:
                return nil
            default:
                return nil  // Empty collection result
            }
        }

        // Convert to collection
        let collection: [any EcoreValue]
        if let valueArray = sourceValue as? EcoreValueArray {
            // Unwrap EcoreValueArray to get the underlying values
            collection = valueArray.values
        } else if let array = sourceValue as? [any EcoreValue] {
            collection = array
        } else {
            // Single element becomes single-element collection
            collection = [sourceValue]
        }

        // Execute operation
        switch operation {
        case .select:
            let result = try await select(collection, context: context)
            return EcoreValueArray(result)
        case .reject:
            let result = try await reject(collection, context: context)
            return EcoreValueArray(result)
        case .collect:
            let result = try await collect(collection, context: context)
            return EcoreValueArray(result)
        case .any, .exists:
            return try await any(collection, context: context)
        case .forAll:
            return try await forAll(collection, context: context)
        case .size:
            return collection.count
        case .isEmpty:
            return collection.isEmpty
        case .notEmpty:
            return !collection.isEmpty
        case .first:
            return collection.first
        case .last:
            return collection.last
        }
    }

    // MARK: - Operation Implementations

    /// Filters collection to elements matching the condition.
    @MainActor
    private func select(
        _ collection: [any EcoreValue],
        context: AQLExecutionContext
    ) async throws -> [any EcoreValue] {
        guard let iterator = iterator, let body = body else {
            throw AQLExecutionError.invalidOperation("select requires iterator and body")
        }

        var result: [any EcoreValue] = []

        for element in collection {
            // Push scope and bind iterator
            context.pushScope()
            context.setVariable(iterator, value: element)

            // Evaluate condition
            let conditionResult = try await body.evaluate(in: context)

            // Pop scope
            context.popScope()

            // Add if condition is true
            if let boolResult = conditionResult as? Bool, boolResult {
                result.append(element)
            }
        }

        return result
    }

    /// Filters collection to elements not matching the condition.
    @MainActor
    private func reject(
        _ collection: [any EcoreValue],
        context: AQLExecutionContext
    ) async throws -> [any EcoreValue] {
        guard let iterator = iterator, let body = body else {
            throw AQLExecutionError.invalidOperation("reject requires iterator and body")
        }

        var result: [any EcoreValue] = []

        for element in collection {
            // Push scope and bind iterator
            context.pushScope()
            context.setVariable(iterator, value: element)

            // Evaluate condition
            let conditionResult = try await body.evaluate(in: context)

            // Pop scope
            context.popScope()

            // Add if condition is false or not boolean
            if let boolResult = conditionResult as? Bool, !boolResult {
                result.append(element)
            } else if conditionResult == nil {
                result.append(element)
            }
        }

        return result
    }

    /// Transforms each element using the body expression.
    @MainActor
    private func collect(
        _ collection: [any EcoreValue],
        context: AQLExecutionContext
    ) async throws -> [any EcoreValue] {
        guard let iterator = iterator, let body = body else {
            throw AQLExecutionError.invalidOperation("collect requires iterator and body")
        }

        var result: [any EcoreValue] = []

        for element in collection {
            // Push scope and bind iterator
            context.pushScope()
            context.setVariable(iterator, value: element)

            // Evaluate transformation
            let transformedValue = try await body.evaluate(in: context)

            // Pop scope
            context.popScope()

            // Add transformed value (even if null)
            if let transformedValue = transformedValue {
                result.append(transformedValue)
            }
        }

        return result
    }

    /// Returns true if any element matches the condition.
    @MainActor
    private func any(
        _ collection: [any EcoreValue],
        context: AQLExecutionContext
    ) async throws -> Bool {
        guard let iterator = iterator, let body = body else {
            throw AQLExecutionError.invalidOperation("any requires iterator and body")
        }

        for element in collection {
            // Push scope and bind iterator
            context.pushScope()
            context.setVariable(iterator, value: element)

            // Evaluate condition
            let conditionResult = try await body.evaluate(in: context)

            // Pop scope
            context.popScope()

            // Return true if condition is true
            if let boolResult = conditionResult as? Bool, boolResult {
                return true
            }
        }

        return false
    }

    /// Returns true if all elements match the condition.
    @MainActor
    private func forAll(
        _ collection: [any EcoreValue],
        context: AQLExecutionContext
    ) async throws -> Bool {
        guard let iterator = iterator, let body = body else {
            throw AQLExecutionError.invalidOperation("forAll requires iterator and body")
        }

        for element in collection {
            // Push scope and bind iterator
            context.pushScope()
            context.setVariable(iterator, value: element)

            // Evaluate condition
            let conditionResult = try await body.evaluate(in: context)

            // Pop scope
            context.popScope()

            // Return false if condition is false or not boolean
            if let boolResult = conditionResult as? Bool {
                if !boolResult {
                    return false
                }
            } else {
                // Non-boolean or null is treated as false
                return false
            }
        }

        return true
    }
}
