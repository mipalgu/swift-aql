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
/// The context evaluates expressions with the ``options`` it holds. Contexts created with
/// ``init(executionEngine:options:serviceProviders:)`` or ``init(options:unsetFeatureReads:serviceProviders:)``
/// use the options given; contexts created with the initialisers of version 0.6 use
/// ``AQLOptions/legacy`` so that they keep computing what they computed in that version.
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
/// let context = AQLExecutionContext(executionEngine: engine, options: .standard)
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

    /// The options that choose between the current behaviour and that of version 0.6.
    ///
    /// Changing ``AQLOptions/containerLookup`` drops the containers cached while
    /// ``cachesContainmentIndex`` is on.
    public var options: AQLOptions {
        didSet {
            if options.containerLookup != oldValue.containerLookup { invalidateContainmentIndex() }
        }
    }

    /// Whether `indexOf` and `lastIndexOf` on collections return 1-based positions (0 if absent) as AQL specifies.
    ///
    /// The default (`true`) follows the AQL specification. Set it to `false` to get the earlier
    /// behaviour of this package: 0-based positions, -1 if absent.
    public var usesOneBasedIndexOf: Bool = true

    /// Whether the containers found by containment queries are cached between calls.
    ///
    /// Without caching, every call of `eContainer()`, `ancestors()`, `siblings()`,
    /// `precedingSiblings()` or `followingSiblings()` asks the registered resources for the
    /// container of each object it looks at, so the answers always reflect the current models.
    /// With caching, each object's container is looked up once and reused until the models
    /// may have changed, which saves the lookups when the same objects are queried repeatedly.
    /// When ``AQLOptions/containerLookup`` is ``AQLContainerLookup/registeredObjects``, the
    /// containers of all registered objects are found together and reused in the same way.
    ///
    /// The cache is dropped when a resource is added with ``addResource(_:)``, after each call
    /// of a service that declares ``AQLService/modifiesModels``, and when caching is switched
    /// off. Any other change to the registered models while caching is on (for example by
    /// code that sets features through a ``Resource`` between evaluations) must be followed
    /// by a call of ``invalidateContainmentIndex()``.
    public var cachesContainmentIndex: Bool = false {
        didSet {
            if !cachesContainmentIndex { invalidateContainmentIndex() }
        }
    }

    /// The containers looked up while caching, keyed by child identifier (`nil` for none).
    private var cachedContainers: [EUUID: (any EObject)?] = [:]

    /// The containers found among the registered objects while caching, keyed by child
    /// identifier.
    private var containmentIndex: [EUUID: any EObject]?

    /// How many times the registered resources have been asked for a container.
    private(set) var containerLookups = 0

    // MARK: - Initialisation

    /// Creates a new AQL execution context with the given options.
    ///
    /// - Parameters:
    ///   - executionEngine: The ECore execution engine to delegate to.
    ///   - options: The options to evaluate expressions with, such as ``AQLOptions/standard``.
    ///   - serviceProviders: Providers to register immediately (earlier entries have lower precedence).
    public init(
        executionEngine: ECoreExecutionEngine,
        options: AQLOptions,
        serviceProviders: [any AQLServiceProvider] = []
    ) {
        self.executionEngine = executionEngine
        self.options = options
        self.services = Self.registry(of: serviceProviders)
    }

    /// Creates a new AQL execution context that behaves as in version 0.6.
    ///
    /// The context evaluates expressions with ``AQLOptions/legacy``.
    ///
    /// - Parameters:
    ///   - executionEngine: The ECore execution engine to delegate to.
    ///   - serviceProviders: Providers to register immediately (earlier entries have lower precedence).
    @available(
        *, deprecated,
        message: "Use init(executionEngine:options:serviceProviders:); pass options: .legacy to keep the behaviour of version 0.6"
    )
    public init(
        executionEngine: ECoreExecutionEngine,
        serviceProviders: [any AQLServiceProvider] = []
    ) {
        self.executionEngine = executionEngine
        self.options = .legacy
        self.services = Self.registry(of: serviceProviders)
    }

    /// Creates a new AQL execution context with an execution engine of its own and the given
    /// options.
    ///
    /// The context creates an ``ECoreExecutionEngine`` without registered models, which suits
    /// expressions that only navigate the objects bound to their variables. Unless told
    /// otherwise, the engine reads an unset feature as its default value, as the Eclipse
    /// Modeling Framework does; pass ``UnsetFeatureReads/undefined`` to read unset features
    /// as `nil` instead.
    ///
    /// - Parameters:
    ///   - options: The options to evaluate expressions with, such as ``AQLOptions/standard``.
    ///   - unsetFeatureReads: How navigation reads features that have not been set.
    ///   - serviceProviders: Providers to register immediately (earlier entries have lower precedence).
    public convenience init(
        options: AQLOptions,
        unsetFeatureReads: UnsetFeatureReads = .defaults,
        serviceProviders: [any AQLServiceProvider] = []
    ) {
        self.init(
            executionEngine: ECoreExecutionEngine(models: [:], unsetFeatureReads: unsetFeatureReads),
            options: options, serviceProviders: serviceProviders)
    }

    /// Creates a new AQL execution context with an execution engine of its own that behaves
    /// as in version 0.6.
    ///
    /// The context evaluates expressions with ``AQLOptions/legacy``. It creates an
    /// ``ECoreExecutionEngine`` without registered models, which reads an unset feature as
    /// its default value unless told otherwise; pass ``UnsetFeatureReads/undefined`` to read
    /// unset features as `nil` instead.
    ///
    /// - Parameters:
    ///   - unsetFeatureReads: How navigation reads features that have not been set.
    ///   - serviceProviders: Providers to register immediately (earlier entries have lower precedence).
    @available(
        *, deprecated,
        message: "Use init(options:unsetFeatureReads:serviceProviders:); pass options: .legacy to keep the behaviour of version 0.6"
    )
    public convenience init(
        unsetFeatureReads: UnsetFeatureReads = .defaults,
        serviceProviders: [any AQLServiceProvider] = []
    ) {
        self.init(
            executionEngine: ECoreExecutionEngine(models: [:], unsetFeatureReads: unsetFeatureReads),
            options: .legacy, serviceProviders: serviceProviders)
    }

    /// A service registry holding the standard library and the given providers.
    private static func registry(of providers: [any AQLServiceProvider]) -> AQLServiceRegistry {
        var registry = AQLServiceRegistry()
        for provider in providers { registry.register(provider) }
        return registry
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
        invalidateContainmentIndex()
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

    /// Drops the cached containers (see ``cachesContainmentIndex``).
    public func invalidateContainmentIndex() {
        cachedContainers = [:]
        containmentIndex = nil
    }

    /// The object that contains the object with the given identifier.
    ///
    /// The container is looked up as ``AQLOptions/containerLookup`` says.
    ///
    /// - Parameter id: The identifier of the contained object.
    /// - Returns: The container, or `nil` if none is found.
    /// - Throws: Any error raised while reading the contents of registered objects.
    func container(of id: EUUID) async throws -> (any EObject)? {
        switch options.containerLookup {
        case .resources: return await resourceContainer(of: id)
        case .registeredObjects: return try await registeredParents()[id]
        }
    }

    /// The object that a registered resource knows to contain the object with the given
    /// identifier.
    ///
    /// The registered resources are asked in the order they were added, and the first one
    /// that knows a container answers.
    ///
    /// - Parameter id: The identifier of the contained object.
    /// - Returns: The container, or `nil` if no registered resource holds the object in a
    ///   containment reference.
    private func resourceContainer(of id: EUUID) async -> (any EObject)? {
        if cachesContainmentIndex, let cached = cachedContainers[id] { return cached }
        containerLookups += 1
        var found: (any EObject)?
        for resource in resources {
            if let entry = await resource.container(ofIdentifier: id) {
                found = entry.container
                break
            }
        }
        if cachesContainmentIndex { cachedContainers[id] = .some(found) }
        return found
    }

    /// The container of every object claimed by a registered object, keyed by the
    /// identifier of the contained object.
    ///
    /// The objects that the registered resources list are searched in resource order, and
    /// the last claim on an object wins.
    ///
    /// - Returns: The containers of all objects held in containment references of the
    ///   registered objects.
    /// - Throws: Any error raised while reading the contents of registered objects.
    private func registeredParents() async throws -> [EUUID: any EObject] {
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

    // MARK: - Collections

    /// The collection kind that operations on a value keep.
    ///
    /// - Parameter value: The value to inspect.
    /// - Returns: The kind of a collection value while ``AQLOptions/collectionKinds`` is
    ///   ``AQLCollectionKinds/distinguished``, otherwise, and for a value that is not a
    ///   collection, ``EcoreCollectionKind/sequence``.
    func collectionKind(of value: (any EcoreValue)?) -> EcoreCollectionKind {
        guard options.collectionKinds == .distinguished else { return .sequence }
        return AQLValues.kind(of: value) ?? .sequence
    }

    /// Creates a collection of the given kind as the options of this context say.
    ///
    /// For an ordered set or a set, an element equal to an earlier one is left out. While
    /// ``AQLOptions/collectionKinds`` is ``AQLCollectionKinds/sequences``, the collection
    /// created is a sequence.
    ///
    /// - Parameters:
    ///   - elements: The elements.
    ///   - kind: The kind of collection to create.
    /// - Returns: The collection value.
    func collection(_ elements: [any EcoreValue], kind: EcoreCollectionKind) -> EcoreValueArray {
        let collection = AQLValues.collection(elements, kind: kind)
        guard options.collectionKinds == .sequences else { return collection }
        return AQLValues.collection(collection.values)
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
    /// Collections are navigated element by element and the results flattened into a collection
    /// of the same kind (so navigating from an ordered set or a set leaves out repeated results,
    /// unless ``AQLOptions/collectionKinds`` is ``AQLCollectionKinds/sequences``). When a derived,
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
            return collection(collected, kind: collectionKind(of: object))
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
        return try await service.invoke(
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
