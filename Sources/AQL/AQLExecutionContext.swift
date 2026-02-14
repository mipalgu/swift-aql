//
//  AQLExecutionContext.swift
//  AQL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import OrderedCollections

/// Execution context for Acceleo Query Language (AQL) expressions.
///
/// The AQL execution context manages variables, model access, and the delegation
/// of computation to the underlying `ECoreExecutionEngine`. AQL focuses on
/// efficient querying and navigation without side effects.
///
/// ## Architecture
///
/// - **Coordination**: Handled on `@MainActor`.
/// - **Computation**: Delegated to `ECoreExecutionEngine` actor.
///
/// ## Example Usage
///
/// ```swift
/// let engine = ECoreExecutionEngine(...)
/// let context = AQLExecutionContext(executionEngine: engine)
/// context.setVariable("self", value: myObject)
/// let result = try await expression.evaluate(in: context)
/// ```
@MainActor
public final class AQLExecutionContext: Sendable {

    // MARK: - Properties

    /// The underlying ECore execution engine for heavy computation.
    public let executionEngine: ECoreExecutionEngine

    /// Variable bindings in the current execution scope.
    private var variables: [String: (any EcoreValue)?] = [:]

    /// Scope stack for nested variable contexts.
    private var scopeStack: [[String: (any EcoreValue)?]] = []

    /// Debug mode flag.
    public var debug: Bool = false

    // MARK: - Initialisation

    /// Creates a new AQL execution context.
    ///
    /// - Parameter executionEngine: The ECore execution engine to delegate to.
    public init(executionEngine: ECoreExecutionEngine) {
        self.executionEngine = executionEngine
    }

    // MARK: - Variable Management

    /// Set a variable value in the current scope.
    ///
    /// - Parameters:
    ///   - name: Variable name
    ///   - value: Variable value
    public func setVariable(_ name: String, value: (any EcoreValue)?) {
        variables[name] = value
    }

    /// Get a variable value from the current scope or scope stack.
    ///
    /// - Parameter name: Variable name
    /// - Returns: Variable value if found
    /// - Throws: `AQLExecutionError` if variable not found
    public func getVariable(_ name: String) async throws -> (any EcoreValue)? {
        // Check current scope first
        if let value = variables[name] {
            return value
        }

        // Check scope stack
        for scope in scopeStack.reversed() {
            if let value = scope[name] {
                return value
            }
        }

        // AQL implicit 'self' lookup: if not found as a variable, try to find it as a property on 'self'
        if name != "self" {
            // Use local try? await to avoid recursion issues or error propagation if self isn't there
            if let selfObject = (try? await getVariable("self")) as? (any EObject) {
                // Try to navigate from self
                // Note: In strict AQL, this might only happen if the variable lookup fails.
                if let result = try? await executionEngine.navigate(
                    from: selfObject, property: name)
                {
                    return result
                }
            }
        }

        throw AQLExecutionError.variableNotFound(name)
    }

    /// Push a new variable scope onto the stack.
    public func pushScope() {
        scopeStack.append(variables)
        variables = [:]
    }

    /// Pop the current variable scope from the stack.
    public func popScope() {
        guard !scopeStack.isEmpty else { return }
        variables = scopeStack.removeLast()
    }

    // MARK: - Navigation Operations

    /// Navigate a property from a source object using the execution engine.
    ///
    /// - Parameters:
    ///   - object: Source object
    ///   - property: Property name
    /// - Returns: Navigation result, or nil if source is nil or not an EObject
    public func navigate(from object: (any EcoreValue)?, property: String) async throws -> (
        any EcoreValue
    )? {
        guard let eObject = object as? (any EObject) else {
            // Return nil for nil sources or non-EObject sources (null-safe navigation)
            return nil
        }

        return try await executionEngine.navigate(from: eObject, property: property)
    }
}

/// Errors that can occur during AQL execution.
public enum AQLExecutionError: Error, LocalizedError, Sendable {
    case variableNotFound(String)
    case typeError(String)
    case invalidOperation(String)

    public var errorDescription: String? {
        switch self {
        case .variableNotFound(let name):
            return "Variable '\(name)' not found"
        case .typeError(let message):
            return "Type error: \(message)"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        }
    }
}
