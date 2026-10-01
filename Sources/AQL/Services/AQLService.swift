//
//  AQLService.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Receiver Matching

/// Describes which receivers a service can be invoked on.
///
/// A service is only considered by the dispatcher when its receiver
/// requirement accepts the evaluated receiver of the call. The requirement is
/// evaluated after the receiver expression has been evaluated, so services
/// with the same name can coexist for different receiver kinds (for example
/// `size` on strings and on collections).
public enum AQLReceiver: Sendable {
    /// Any receiver, including a null receiver, as long as the call has a receiver expression.
    case any

    /// Any receiver other than null.
    case nonNull

    /// Calls without a receiver expression, such as `name(args)`.
    case standalone

    /// String receivers.
    case string

    /// Collection receivers (sequences and ordered sets).
    case collection

    /// Receivers that are `EObject` instances (dynamic or native).
    case object

    /// Integer and real receivers.
    case number

    /// Boolean receivers.
    case boolean

    /// Type descriptor receivers (see ``AQLTypeDescriptor``).
    case type

    /// Receivers accepted by the given predicate.
    case custom(@Sendable ((any EcoreValue)?) -> Bool)

    /// Checks whether a receiver satisfies this requirement.
    ///
    /// - Parameters:
    ///   - value: The evaluated receiver (nil for null or for a missing receiver).
    ///   - hasReceiver: Whether the call has a receiver expression.
    /// - Returns: `true` if the service may be invoked on the receiver.
    public func matches(_ value: (any EcoreValue)?, hasReceiver: Bool) -> Bool {
        if case .standalone = self { return !hasReceiver }
        guard hasReceiver else { return false }
        switch self {
        case .any: return true
        case .standalone: return false
        case .nonNull: return value != nil
        case .string: return value is String
        case .collection: return AQLValues.elements(of: value) != nil
        case .object: return value is any EObject
        case .number: return AQLValues.isNumber(value)
        case .boolean: return value is Bool
        case .type: return value is AQLTypeDescriptor
        case .custom(let predicate): return predicate(value)
        }
    }
}

// MARK: - Service Invocation

/// The data handed to a service implementation when it is invoked.
///
/// The receiver and arguments are already evaluated. Services that need to
/// navigate the model, resolve references or evaluate lambdas do so through
/// the execution context.
public struct AQLServiceCall: Sendable {
    /// The name under which the service was invoked.
    public let name: String

    /// The evaluated receiver (nil for null or for standalone calls).
    public let receiver: (any EcoreValue)?

    /// The evaluated arguments, in call order.
    public let arguments: [(any EcoreValue)?]

    /// The execution context of the call.
    public let context: AQLExecutionContext

    /// Creates a service call description.
    ///
    /// - Parameters:
    ///   - name: The invoked service name.
    ///   - receiver: The evaluated receiver.
    ///   - arguments: The evaluated arguments.
    ///   - context: The execution context.
    public init(
        name: String, receiver: (any EcoreValue)?, arguments: [(any EcoreValue)?],
        context: AQLExecutionContext
    ) {
        self.name = name
        self.receiver = receiver
        self.arguments = arguments
        self.context = context
    }

    /// Returns the argument at the given position, or nil if null or absent.
    ///
    /// - Parameter index: The zero-based argument position.
    /// - Returns: The argument value.
    public func argument(_ index: Int) -> (any EcoreValue)? {
        guard index < arguments.count else { return nil }
        return arguments[index]
    }

    /// The receiver as a string.
    ///
    /// - Throws: ``AQLExecutionError/typeError(_:)`` if the receiver is not a string.
    public func receiverString() throws -> String {
        guard let value = receiver as? String else {
            throw AQLExecutionError.typeError("\(name) requires a string receiver")
        }
        return value
    }

    /// The receiver as a list of elements (null becomes empty, a single value a singleton).
    public func receiverElements() -> [any EcoreValue] {
        AQLValues.coerceToCollection(receiver)
    }

    /// The argument at the given position as a string.
    ///
    /// - Parameter index: The zero-based argument position.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` if the argument is not a string.
    public func string(_ index: Int) throws -> String {
        guard let value = argument(index) as? String else {
            throw AQLExecutionError.typeError("\(name) requires a string argument at position \(index + 1)")
        }
        return value
    }

    /// The argument at the given position as an integer.
    ///
    /// - Parameter index: The zero-based argument position.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` if the argument is not an integer.
    public func integer(_ index: Int) throws -> Int {
        guard let value = AQLValues.integer(argument(index)) else {
            throw AQLExecutionError.typeError("\(name) requires an integer argument at position \(index + 1)")
        }
        return value
    }

    /// The argument at the given position as a collection.
    ///
    /// - Parameter index: The zero-based argument position.
    /// - Returns: The elements (null becomes empty, a single value a singleton).
    public func elements(_ index: Int) -> [any EcoreValue] {
        AQLValues.coerceToCollection(argument(index))
    }

    /// The argument at the given position as a lambda.
    ///
    /// - Parameter index: The zero-based argument position.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` if the argument is not a lambda.
    public func lambda(_ index: Int) throws -> AQLLambda {
        guard let value = argument(index) as? AQLLambda else {
            throw AQLExecutionError.typeError("\(name) requires an iterator expression argument")
        }
        return value
    }

    /// The argument at the given position as a type descriptor.
    ///
    /// Type descriptors, `EClass` values and bare identifiers naming a type are accepted.
    ///
    /// - Parameter index: The zero-based argument position.
    /// - Throws: ``AQLExecutionError/typeError(_:)`` if the argument does not denote a type.
    public func type(_ index: Int) throws -> AQLTypeDescriptor {
        guard let descriptor = AQLTypeDescriptor(value: argument(index)) else {
            throw AQLExecutionError.typeError("\(name) requires a type argument")
        }
        return descriptor
    }
}

/// The signature of a service implementation.
///
/// Implementations run on the main actor (the execution context is main
/// actor isolated) and may suspend, for example to resolve references through
/// the execution engine.
public typealias AQLServiceImplementation =
    @MainActor @Sendable (AQLServiceCall) async throws -> (any EcoreValue)?

// MARK: - Service

/// A named operation callable as `receiver.name(args)`, `receiver->name(args)` or `name(args)`.
///
/// A service declares the receivers it accepts and the number of arguments
/// it takes. When several services share a name, the dispatcher picks the
/// first whose receiver requirement and arity accept the call, searching
/// the most recently registered provider first.
public struct AQLService: Sendable {
    /// The service name.
    public let name: String

    /// The receivers this service accepts.
    public let receiver: AQLReceiver

    /// The accepted argument counts.
    public let arity: ClosedRange<Int>

    /// Whether bare identifiers (and `pkg::Type` names) passed as arguments denote types.
    ///
    /// When `true`, an argument written as an unbound identifier is passed to the
    /// implementation as an ``AQLTypeDescriptor`` rather than being looked up as a variable.
    public let acceptsTypeArguments: Bool

    /// The implementation.
    public let implementation: AQLServiceImplementation

    /// Creates a service.
    ///
    /// - Parameters:
    ///   - name: The service name.
    ///   - receiver: The receivers accepted (default: any receiver).
    ///   - arity: The accepted argument counts (default: none).
    ///   - acceptsTypeArguments: Whether bare identifier arguments denote types.
    ///   - implementation: The implementation.
    public init(
        _ name: String,
        receiver: AQLReceiver = .any,
        arity: ClosedRange<Int> = 0...0,
        acceptsTypeArguments: Bool = false,
        implementation: @escaping AQLServiceImplementation
    ) {
        self.name = name
        self.receiver = receiver
        self.arity = arity
        self.acceptsTypeArguments = acceptsTypeArguments
        self.implementation = implementation
    }

    /// Creates a service taking exactly the given number of arguments.
    ///
    /// - Parameters:
    ///   - name: The service name.
    ///   - receiver: The receivers accepted.
    ///   - arity: The exact argument count.
    ///   - acceptsTypeArguments: Whether bare identifier arguments denote types.
    ///   - implementation: The implementation.
    public init(
        _ name: String,
        receiver: AQLReceiver = .any,
        arity: Int,
        acceptsTypeArguments: Bool = false,
        implementation: @escaping AQLServiceImplementation
    ) {
        self.init(
            name, receiver: receiver, arity: arity...arity,
            acceptsTypeArguments: acceptsTypeArguments, implementation: implementation)
    }

    /// Creates a copy of this service registered under another name.
    ///
    /// - Parameter alias: The additional name.
    /// - Returns: A service with identical behaviour under the new name.
    public func aliased(as alias: String) -> AQLService {
        AQLService(
            alias, receiver: receiver, arity: arity,
            acceptsTypeArguments: acceptsTypeArguments, implementation: implementation)
    }
}

// MARK: - Provider

/// A source of services that a client registers with an execution context.
///
/// Conforming types describe the services they offer. Typical providers are
/// small value types, for example one per model-specific helper library.
///
/// ```swift
/// struct GreetingServices: AQLServiceProvider {
///     var services: [AQLService] {
///         [AQLService("greet", receiver: .string, arity: 1) { call in
///             "\(try call.string(0)), \(try call.receiverString())"
///         }]
///     }
/// }
/// context.register(GreetingServices())
/// // 'World'.greet('Hello') evaluates to 'Hello, World'
/// ```
///
/// Dispatch order for a call with parentheses: services of providers
/// registered on the context (most recent first), then the standard library.
/// Navigation without parentheses first tries structural features and only
/// then zero-argument registered services.
public protocol AQLServiceProvider: Sendable {
    /// The services offered by this provider.
    var services: [AQLService] { get }
}

// MARK: - Registry

/// The set of services known to an execution context.
///
/// The registry holds the standard library and the services registered by
/// clients. Lookups prefer client services (latest registration first).
public struct AQLServiceRegistry: Sendable {
    private var custom: [String: [AQLService]] = [:]
    private var standard: [String: [AQLService]] = [:]

    /// Creates a registry.
    ///
    /// - Parameter includingStandardLibrary: Whether to include the built-in library.
    public init(includingStandardLibrary: Bool = true) {
        if includingStandardLibrary {
            for provider in AQLStandardLibrary.providers {
                for service in provider.services {
                    standard[service.name, default: []].append(service)
                }
            }
        }
    }

    /// Registers a provider; its services take precedence over earlier registrations.
    ///
    /// - Parameter provider: The provider to register.
    public mutating func register(_ provider: some AQLServiceProvider) {
        for service in provider.services.reversed() {
            custom[service.name, default: []].insert(service, at: 0)
        }
    }

    /// Finds the service for a call.
    ///
    /// - Parameters:
    ///   - name: The service name.
    ///   - receiver: The evaluated receiver.
    ///   - hasReceiver: Whether the call has a receiver expression.
    ///   - argumentCount: The number of arguments.
    ///   - customOnly: Restrict the search to client-registered services.
    /// - Returns: The first matching service, or nil.
    public func find(
        name: String, receiver: (any EcoreValue)?, hasReceiver: Bool, argumentCount: Int,
        customOnly: Bool = false
    ) -> AQLService? {
        let match: (AQLService) -> Bool = {
            $0.arity.contains(argumentCount) && $0.receiver.matches(receiver, hasReceiver: hasReceiver)
        }
        if let service = custom[name]?.first(where: match) { return service }
        if customOnly { return nil }
        return standard[name]?.first(where: match)
    }
}

/// The standard library: the built-in services available in every context.
public enum AQLStandardLibrary {
    /// The built-in providers, in registration order.
    public static let providers: [any AQLServiceProvider] = [
        AQLObjectServices(), AQLBooleanServices(), AQLNumberServices(), AQLStringServices(),
        AQLCollectionServices(),
    ]
}
