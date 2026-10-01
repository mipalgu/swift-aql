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

    /// The services callable from expressions evaluated in this context.
    ///
    /// The registry starts with the standard library; use ``register(_:)`` to add services.
    public private(set) var services: AQLServiceRegistry

    /// The resources searched by services that need the whole model (`eContainer`, `allInstances`, ...).
    public private(set) var resources: [Resource] = []

    /// Whether `indexOf` and `lastIndexOf` on collections return 1-based positions (0 if absent) as AQL specifies.
    ///
    /// The default (`true`) follows the AQL specification. Set it to `false` to get the earlier
    /// behaviour of this package: 0-based positions, -1 if absent.
    public var usesOneBasedIndexOf: Bool = true

    /// Whether the child-to-parent containment index is cached between calls.
    ///
    /// Caching makes `eContainer()`, `ancestors()` and `siblings()` cheap on large models, but the
    /// cache must be dropped with ``invalidateContainmentIndex()`` after the model changes.
    public var cachesContainmentIndex: Bool = false

    private var containmentIndex: [EUUID: (any EObject)]?

    // MARK: - Initialisation

    /// Creates a new AQL execution context.
    ///
    /// - Parameters:
    ///   - executionEngine: The ECore execution engine to delegate to.
    ///   - serviceProviders: Providers to register immediately (earlier entries have lower precedence).
    public init(
        executionEngine: ECoreExecutionEngine,
        serviceProviders: [any AQLServiceProvider] = []
    ) {
        self.executionEngine = executionEngine
        var registry = AQLServiceRegistry()
        for provider in serviceProviders { registry.register(provider) }
        self.services = registry
    }

    // MARK: - Services

    /// Registers a service provider.
    ///
    /// Services of the provider take precedence over earlier registrations and over
    /// the standard library for calls with the same name, receiver kind and arity.
    ///
    /// - Parameter provider: The provider to register.
    public func register(_ provider: some AQLServiceProvider) {
        services.register(provider)
    }

    /// Adds a resource to the set searched by whole-model services.
    ///
    /// - Parameter resource: The resource holding model objects.
    public func addResource(_ resource: Resource) {
        if !resources.contains(where: { $0 === resource }) { resources.append(resource) }
        containmentIndex = nil
    }

    /// Resolves an object identifier against the registered resources.
    ///
    /// - Parameter id: The object identifier.
    /// - Returns: The object, or nil if no registered resource holds it.
    func resolve(_ id: EUUID) async -> (any EObject)? {
        for resource in resources {
            if let object = await resource.resolve(id) { return object }
        }
        return nil
    }

    /// Drops the cached containment index (see ``cachesContainmentIndex``).
    public func invalidateContainmentIndex() {
        containmentIndex = nil
    }

    /// The parent object of every contained object, keyed by child identifier.
    ///
    /// - Returns: The parents of all objects reachable through containment references of the
    ///   registered resources.
    func parents() async throws -> [EUUID: any EObject] {
        if cachesContainmentIndex, let containmentIndex { return containmentIndex }
        var index: [EUUID: any EObject] = [:]
        for resource in resources {
            for object in await resource.getAllObjects() {
                for child in try await AQLObjectServices.contents(of: object, in: self) {
                    if let child = child as? any EObject { index[child.id] = object }
                }
            }
        }
        if cachesContainmentIndex { containmentIndex = index }
        return index
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

    /// Sets a variable in the outermost scope, visible from every scope.
    ///
    /// Any binding of the same name in an inner scope is removed, so that the new value is
    /// the one every lookup finds, whether or not the caller is inside nested scopes. The
    /// binding outlives the scopes that are active when it is set.
    ///
    /// - Parameters:
    ///   - name: Variable name
    ///   - value: Variable value
    public func setGlobalVariable(_ name: String, value: (any EcoreValue)?) {
        guard !scopeStack.isEmpty else {
            variables[name] = value
            return
        }
        scopeStack[0][name] = value
        for index in scopeStack.indices.dropFirst() { scopeStack[index][name] = nil }
        variables[name] = nil
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
    ///
    /// Collections are navigated element by element and the results flattened. When a derived,
    /// volatile or transient feature of an object has no value (nil or an empty collection), a
    /// client-registered zero-argument service of the same name is called on the object instead,
    /// so that templates can compute such features without writing parentheses.
    /// - Returns: Navigation result, or nil if source is nil or not an EObject
    public func navigate(from object: (any EcoreValue)?, property: String) async throws -> (
        any EcoreValue
    )? {
        if let items = AQLValues.elements(of: object) {
            var collected: [any EcoreValue] = []
            for item in items {
                if let value = try await navigate(from: item, property: property) {
                    collected.append(contentsOf: AQLValues.elements(of: value) ?? [value])
                }
            }
            return EcoreValueArray(collected)
        }
        guard let eObject = object as? (any EObject) else {
            // Return nil for nil sources or non-EObject sources (null-safe navigation)
            return nil
        }

        let value = try await executionEngine.navigate(from: eObject, property: property)
        guard Self.hasNoValue(value), Self.isComputed(property, of: eObject),
            let service = services.find(
                name: property, receiver: eObject, hasReceiver: true, argumentCount: 0,
                customOnly: true)
        else { return value }
        return try await service.implementation(
            AQLServiceCall(name: property, receiver: eObject, arguments: [], context: self))
    }

    private static func hasNoValue(_ value: (any EcoreValue)?) -> Bool {
        guard let value else { return true }
        return AQLValues.elements(of: value)?.isEmpty ?? false
    }

    private static func isComputed(_ property: String, of object: any EObject) -> Bool {
        let feature = (object.eClass as? EClass)?.getStructuralFeature(name: property)
        if let attribute = feature as? EAttribute {
            return attribute.derived || attribute.volatile || attribute.transient
        }
        if let reference = feature as? EReference {
            return reference.derived || reference.volatile || reference.transient
        }
        return false
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
