//
//  AQLIncrementalExpression.swift
//  AQL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

public import ECore
public import EMFBase
import Foundation

/// The difference between two values of an incrementally evaluated expression.
///
/// A change reports the value before and after re-evaluation. For collection values it
/// also lists the elements that were added and removed, counting repeated elements, so
/// that a client can update a view of the result without comparing the collections itself.
/// For other values, the old value counts as removed and the new one as added when they
/// differ.
public struct AQLQueryChange: Sendable {
    /// The value before re-evaluation, or `nil` for null.
    public let oldValue: (any EcoreValue)?

    /// The value after re-evaluation, or `nil` for null.
    public let newValue: (any EcoreValue)?

    /// The elements of the new value that the old value did not hold.
    public let added: [any EcoreValue]

    /// The elements of the old value that the new value no longer holds.
    public let removed: [any EcoreValue]

    /// Whether the value changed.
    ///
    /// A collection whose elements were only reordered has changed even though nothing was
    /// added or removed.
    public let isChanged: Bool

    /// Describes the change between two values.
    ///
    /// - Parameters:
    ///   - oldValue: The value before re-evaluation.
    ///   - newValue: The value after re-evaluation.
    public init(from oldValue: (any EcoreValue)?, to newValue: (any EcoreValue)?) {
        self.oldValue = oldValue
        self.newValue = newValue
        let oldElements = AQLValues.elements(of: oldValue)
        let newElements = AQLValues.elements(of: newValue)
        if oldElements != nil || newElements != nil {
            let before = oldElements ?? oldValue.map { [$0] } ?? []
            let after = newElements ?? newValue.map { [$0] } ?? []
            var remaining: [AnyHashable: Int] = [:]
            for element in before { remaining[Self.key(element), default: 0] += 1 }
            var added: [any EcoreValue] = []
            for element in after {
                let key = Self.key(element)
                if let count = remaining[key], count > 0 {
                    remaining[key] = count - 1
                } else {
                    added.append(element)
                }
            }
            var removed: [any EcoreValue] = []
            for element in before.reversed() {
                let key = Self.key(element)
                if let count = remaining[key], count > 0 {
                    remaining[key] = count - 1
                    removed.append(element)
                }
            }
            self.added = added
            self.removed = removed.reversed()
            self.isChanged =
                !added.isEmpty || !removed.isEmpty || (oldElements == nil) != (newElements == nil)
                || !zip(before, after).allSatisfy { Self.key($0) == Self.key($1) }
        } else {
            let changed = !AQLValues.areEqual(oldValue, newValue)
            self.added = changed ? newValue.map { [$0] } ?? [] : []
            self.removed = changed ? oldValue.map { [$0] } ?? [] : []
            self.isChanged = changed
        }
    }
}

extension AQLQueryChange {
    /// The key by which elements of collection values are compared.
    ///
    /// - Parameter value: An element.
    /// - Returns: The element as a hashable key.
    static func key(_ value: any EcoreValue) -> AnyHashable { AnyHashable(value) }
}

/// An AQL expression whose value is kept up to date as the models change.
///
/// An incremental expression evaluates its expression once while recording what the
/// evaluation reads from the models: the features of the objects navigated, the classes
/// whose instances are enumerated with `allInstances`, and the containment queries made
/// (see ``ModelDependencies``). After the models have been changed through the editing
/// operations of ``Resource``, ``update(for:)`` re-evaluates the expression only if one of
/// the changes affects something that the last evaluation read, and reports the change of
/// the value. This follows the dependency tracking of incremental query engines such as
/// NMF Expressions and VIATRA: a re-evaluated value is always the value that a fresh
/// evaluation over the changed models gives.
///
/// Incremental evaluation is opt-in: evaluating an ``AQLExpression`` directly records
/// nothing and behaves exactly as before.
///
/// ```swift
/// let adults = AQLIncrementalExpression(
///     expression: try AQLParser().parse("Person.allInstances()->select(p | p.age >= 18)"),
///     context: context)
/// _ = try await adults.evaluate()
/// let changes = try await resource.eSetWithChanges(objectId: id, feature: "age", value: 21)
/// if let change = try await adults.update(for: changes) { print(change.added) }
/// ```
///
/// The context should hold the models: each resource must be added with
/// ``AQLExecutionContext/addResource(_:)`` and registered with the context's
/// ``AQLExecutionContext/executionEngine``, so that navigation reads the current state of
/// objects. Object values bound to the expression's variables are replaced by their current
/// state before each evaluation. Calls of client-registered services make the expression
/// depend on every change, because what they read cannot be followed.
@MainActor
public final class AQLIncrementalExpression {
    /// The expression kept up to date.
    public let expression: any AQLExpression

    /// The context the expression is evaluated in.
    public let context: AQLExecutionContext

    /// The values bound to variables during evaluation, by variable name.
    public private(set) var variables: [String: (any EcoreValue)?]

    /// The value of the latest evaluation, or `nil` for null or before the first evaluation.
    public private(set) var value: (any EcoreValue)?

    /// What the latest evaluation read from the models.
    ///
    /// Before the first evaluation, and after an evaluation that failed, the dependencies
    /// are unbounded, so that the next update evaluates the expression.
    public private(set) var dependencies: ModelDependencies

    /// The number of times the expression has been evaluated.
    public private(set) var evaluationCount = 0

    /// Whether the expression has been evaluated successfully at least once.
    public private(set) var hasValue = false

    /// Creates an incremental expression.
    ///
    /// The expression is not evaluated until ``evaluate()`` or ``update(for:)`` is called.
    ///
    /// - Parameters:
    ///   - expression: The expression to keep up to date.
    ///   - context: The context to evaluate the expression in.
    ///   - variables: The values to bind to variables, such as `self`, by name.
    public init(
        expression: any AQLExpression, context: AQLExecutionContext,
        variables: [String: (any EcoreValue)?] = [:]
    ) {
        self.expression = expression
        self.context = context
        self.variables = variables
        var unbounded = ModelDependencies()
        unbounded.recordUnbounded()
        self.dependencies = unbounded
    }

    /// Evaluates the expression, recording what it reads.
    ///
    /// - Returns: The value of the expression.
    /// - Throws: Any error raised by the evaluation; the dependencies then become unbounded.
    @discardableResult
    public func evaluate() async throws -> (any EcoreValue)? {
        evaluationCount += 1
        await refreshVariables()
        context.pushScope()
        defer { context.popScope() }
        for (name, value) in variables { context.setVariable(name, value: value) }
        do {
            let (result, recorded) = try await context.recordingDependencies {
                try await expression.evaluate(in: context)
            }
            value = result
            dependencies = recorded
            hasValue = true
            return result
        } catch {
            var unbounded = ModelDependencies()
            unbounded.recordUnbounded()
            dependencies = unbounded
            throw error
        }
    }

    /// Decides whether changes may alter the value of the expression.
    ///
    /// - Parameter impact: The summary of the changes.
    /// - Returns: `true` if the latest evaluation read something that the changes affect.
    public func isAffected(by impact: ModelChangeImpact) -> Bool {
        dependencies.isAffected(by: impact)
    }

    /// Brings the value up to date after changes to the models.
    ///
    /// The cached navigation results of the context's execution engine and its cached
    /// containers are discarded for the changed parts of the models first (see
    /// ``ECoreExecutionEngine/invalidateCaches(for:)``). The expression is then re-evaluated
    /// if, and only if, the changes affect what its latest evaluation read.
    ///
    /// - Parameter changes: The changes made to the models since the latest update, in order.
    /// - Returns: The change of the value, or `nil` if the expression was not re-evaluated.
    /// - Throws: Any error raised by the re-evaluation.
    @discardableResult
    public func update(for changes: [ResourceChange]) async throws -> AQLQueryChange? {
        let impact = await ModelChangeImpact(changes: changes, in: context.resources)
        await Self.invalidateCaches(of: context, for: changes, impact: impact)
        return try await update(for: impact)
    }

    /// Re-evaluates the expression if changes whose caches have been invalidated affect it.
    ///
    /// - Parameter impact: The summary of the changes.
    /// - Returns: The change of the value, or `nil` if the expression was not re-evaluated.
    /// - Throws: Any error raised by the re-evaluation.
    func update(for impact: ModelChangeImpact) async throws -> AQLQueryChange? {
        guard !hasValue || dependencies.isAffected(by: impact) else { return nil }
        let old = value
        let new = try await evaluate()
        return AQLQueryChange(from: old, to: new)
    }

    /// Makes the next update re-evaluate the expression whatever the changes.
    func invalidate() {
        var unbounded = ModelDependencies()
        unbounded.recordUnbounded()
        dependencies = unbounded
    }

    /// Discards the cached state of a context that changes may have made stale.
    ///
    /// - Parameters:
    ///   - context: The context whose caches to discard.
    ///   - changes: The changes made to the models.
    ///   - impact: The summary of the changes.
    static func invalidateCaches(
        of context: AQLExecutionContext, for changes: [ResourceChange], impact: ModelChangeImpact
    ) async {
        guard !changes.isEmpty else { return }
        await context.executionEngine.invalidateCaches(for: changes)
        if impact.changesContainmentStructure || impact.isUnbounded {
            context.invalidateContainmentIndex()
        }
    }

    /// Replaces the objects bound to variables by their current state.
    private func refreshVariables() async {
        for (name, value) in variables {
            variables[name] = await current(value)
        }
    }

    /// The current state of a value, with objects re-read from the context's resources.
    ///
    /// - Parameter value: A value bound to a variable.
    /// - Returns: The value with each object replaced by its current state, if a resource
    ///   still holds it.
    private func current(_ value: (any EcoreValue)?) async -> (any EcoreValue)? {
        if let object = value as? any EObject {
            return await context.resolve(object.id) ?? object
        }
        if let collection = value as? EcoreValueArray {
            var elements: [any EcoreValue] = []
            elements.reserveCapacity(collection.values.count)
            for element in collection.values {
                elements.append(await current(element) ?? element)
            }
            return EcoreValueArray(elements, kind: collection.kind)
        }
        return value
    }
}

/// The registration of an expression with an ``AQLQueryObserver``.
public struct AQLQueryRegistration: Hashable, Sendable {
    /// The identifier of the registration.
    public let identifier: UUID

    /// Creates a registration identifier.
    ///
    /// - Parameter identifier: The identifier; a new one by default.
    public init(identifier: UUID = UUID()) {
        self.identifier = identifier
    }
}

/// The re-evaluation of one registered expression by an ``AQLQueryObserver``.
public struct AQLQueryUpdate: Sendable {
    /// The registration of the re-evaluated expression.
    public let registration: AQLQueryRegistration

    /// The change of its value.
    public let change: AQLQueryChange

    /// Creates an update record.
    ///
    /// - Parameters:
    ///   - registration: The registration of the expression.
    ///   - change: The change of its value.
    public init(registration: AQLQueryRegistration, change: AQLQueryChange) {
        self.registration = registration
        self.change = change
    }
}

/// Keeps a set of incremental expressions up to date as the models of a context change.
///
/// An observer watches the resources of an ``AQLExecutionContext`` for changes, which
/// their editing operations report (see ``Resource/addChangeObserver(_:)``). On
/// ``refresh()``, it summarises the changes collected since the previous refresh once,
/// discards the stale cached state of the context, finds the registered expressions that
/// the changes affect through a ``ModelDependencyIndex``, re-evaluates only those, and
/// reports their changes, both as the result and to each expression's handler. The cost of
/// a refresh grows with the size of the changes and of the affected expressions, not with
/// the number of registered expressions.
///
/// ```swift
/// let observer = AQLQueryObserver(context: context)
/// await observer.start()
/// let registration = try await observer.register(adults) { change in
///     print("now \(AQLValues.description(of: change.newValue))")
/// }
/// try await resource.eSetWithChanges(objectId: id, feature: "age", value: 21)
/// let updates = try await observer.refresh()
/// ```
@MainActor
public final class AQLQueryObserver {
    /// The context whose models are watched.
    public let context: AQLExecutionContext

    /// The changes reported by the watched resources and not yet processed.
    private let queue = ResourceChangeQueue()

    /// The registrations with the watched resources.
    private var observations: [(resource: Resource, observation: ResourceChangeObservation)] = []

    /// The registered expressions, by registration.
    private var expressions: [AQLQueryRegistration: AQLIncrementalExpression] = [:]

    /// The registration order of the expressions, so that refreshes report in that order.
    private var order: [AQLQueryRegistration] = []

    /// The handlers to call with the changes of each registered expression.
    private var handlers: [AQLQueryRegistration: @MainActor (AQLQueryChange) -> Void] = [:]

    /// The dependencies of the registered expressions.
    private var index = ModelDependencyIndex<AQLQueryRegistration>()

    /// Creates an observer for the models of a context.
    ///
    /// The observer does not watch the models until ``start()`` is called.
    ///
    /// - Parameter context: The context whose resources to watch.
    public init(context: AQLExecutionContext) {
        self.context = context
    }

    /// Whether the observer is watching the resources of its context.
    public var isObserving: Bool { !observations.isEmpty }

    /// The number of changes collected and not yet processed by ``refresh()``.
    public var pendingChangeCount: Int { queue.count }

    /// The number of registered expressions.
    public var registrationCount: Int { expressions.count }

    /// The number of model parts that the registered expressions are recorded to depend on.
    ///
    /// It is the ``ModelDependencyIndex/entryCount`` of the index of their dependencies.
    public var dependencyEntryCount: Int { index.entryCount }

    /// Starts watching the resources of the context for changes.
    ///
    /// Resources added to the context later are not watched until ``start()`` is called
    /// again. Calling it again does not register twice with a resource.
    public func start() async {
        for resource in context.resources where !observations.contains(where: { $0.resource === resource }) {
            observations.append((resource, await queue.observe(resource)))
        }
    }

    /// Stops watching the resources of the context.
    ///
    /// Changes collected and not yet processed are kept for the next ``refresh()``.
    public func stop() async {
        for (resource, observation) in observations {
            await resource.removeChangeObserver(observation)
        }
        observations = []
    }

    /// Registers an expression, evaluates it and keeps it up to date from then on.
    ///
    /// - Parameters:
    ///   - expression: The expression; it must use the observer's context.
    ///   - handler: A handler to call with each change of the expression's value.
    /// - Returns: The registration, for ``unregister(_:)`` and to identify updates.
    /// - Throws: ``AQLExecutionError/invalidOperation(_:)`` if the expression uses another
    ///   context, and any error raised by the evaluation.
    @discardableResult
    public func register(
        _ expression: AQLIncrementalExpression,
        handler: (@MainActor (AQLQueryChange) -> Void)? = nil
    ) async throws -> AQLQueryRegistration {
        guard expression.context === context else {
            throw AQLExecutionError.invalidOperation(
                "An expression registered with a query observer must use the observer's context")
        }
        if !expression.hasValue { try await expression.evaluate() }
        let registration = AQLQueryRegistration()
        expressions[registration] = expression
        order.append(registration)
        handlers[registration] = handler
        index.insert(expression.dependencies, for: registration)
        return registration
    }

    /// Ends the registration of an expression.
    ///
    /// - Parameter registration: The registration to end.
    /// - Returns: The expression that was registered, if the registration was active.
    @discardableResult
    public func unregister(_ registration: AQLQueryRegistration) -> AQLIncrementalExpression? {
        guard let expression = expressions.removeValue(forKey: registration) else { return nil }
        order.removeAll { $0 == registration }
        handlers[registration] = nil
        index.remove(registration)
        return expression
    }

    /// The expression of a registration.
    ///
    /// - Parameter registration: The registration.
    /// - Returns: The registered expression, or `nil` if the registration is not active.
    public func expression(for registration: AQLQueryRegistration) -> AQLIncrementalExpression? {
        expressions[registration]
    }

    /// Brings every registered expression up to date with the changes collected so far.
    ///
    /// - Returns: The updates of the expressions that were re-evaluated, in registration
    ///   order, including those whose value turned out not to change.
    /// - Throws: The first error raised by a re-evaluation; expressions that were not yet
    ///   re-evaluated stay affected and are re-evaluated by the next refresh.
    @discardableResult
    public func refresh() async throws -> [AQLQueryUpdate] {
        let changes = queue.drain()
        return try await apply(changes)
    }

    /// Brings every registered expression up to date with changes reported elsewhere.
    ///
    /// Use this method when the observer does not watch the resources itself, for example
    /// with changes collected by ``Resource/recordingChanges(_:)``.
    ///
    /// - Parameter changes: The changes made to the models, in order.
    /// - Returns: The updates of the expressions that were re-evaluated, in registration order.
    /// - Throws: The first error raised by a re-evaluation.
    @discardableResult
    public func apply(_ changes: [ResourceChange]) async throws -> [AQLQueryUpdate] {
        guard !changes.isEmpty else { return [] }
        let impact = await ModelChangeImpact(changes: changes, in: context.resources)
        await AQLIncrementalExpression.invalidateCaches(of: context, for: changes, impact: impact)
        let affected = index.dependents(affectedBy: impact)
        let pending = order.filter(affected.contains)
        var updates: [AQLQueryUpdate] = []
        for (position, registration) in pending.enumerated() {
            guard let expression = expressions[registration] else { continue }
            do {
                if let change = try await expression.update(for: impact) {
                    updates.append(AQLQueryUpdate(registration: registration, change: change))
                    handlers[registration]?(change)
                }
                index.insert(expression.dependencies, for: registration)
            } catch {
                index.insert(expression.dependencies, for: registration)
                for remaining in pending.dropFirst(position + 1) {
                    guard let stale = expressions[remaining] else { continue }
                    stale.invalidate()
                    index.insert(stale.dependencies, for: remaining)
                }
                throw error
            }
        }
        return updates
    }
}
