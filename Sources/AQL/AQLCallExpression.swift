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
/// While ``AQLOptions/dotCalls`` is ``AQLDotCalls/eachElement``, a call written with a dot on a
/// collection is made on each element of the collection instead, as Eclipse AQL does: an element
/// that is itself a collection has the call made on each of its elements in turn, and the
/// results are collected in a collection of the kind of the receiver. A result that is a
/// collection contributes its elements, and a null result, or an element that has no service
/// of the name for arguments of their types, contributes nothing. The arguments are evaluated
/// once for all elements. When an element has no such service but the collection has one, the
/// call reports a warning with the code ``AQLDiagnosticCode/dotCallOnElements`` in
/// ``AQLExecutionContext/diagnostics``; otherwise it reports a warning with the code
/// ``AQLDiagnosticCode/serviceNotFound`` once for each type of element without the service.
///
/// ## Iterator arguments
///
/// Operations such as `select` take an ``AQLLambdaExpression`` argument. Arguments of services that
/// accept type arguments may be bare identifiers or ``AQLTypeLiteralExpression`` nodes.
public struct AQLCallExpression: AQLExpression {
    /// Where the expression was written, if known.
    public let origin: SourceOrigin

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
    ///   - origin: Where the expression was written, if known.
    public init(
        source: (any AQLExpression)? = nil,
        methodName: String,
        arguments: [any AQLExpression] = [],
        usesArrow: Bool = false,
        origin: SourceOrigin = .init()
    ) {
        self.origin = origin
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
            receiver = Self.arrowReceiver(receiver, in: context)
        } else if hasReceiver, context.options.dotCalls == .eachElement, let collection = receiver,
            AQLValues.elements(of: collection) != nil
        {
            var arguments = AQLCallArguments(argumentExpressions)
            var collectionHasService: Bool?
            return try await context.applyToEachElement(of: collection, named: methodName) { element in
                let result = try await call(on: element, arguments: &arguments, in: context)
                if case .missing = result, collectionHasService == nil {
                    collectionHasService = warnIfCollectionHasService(
                        collection, argumentCount: arguments.count, in: context)
                }
                return result
            } reportingMissing: { types in
                guard collectionHasService != true else { return }
                let argumentTypes: [AQLValueType?] =
                    arguments.evaluatedValues?.map { AQLValueType(of: $0) }
                    ?? Array(repeating: nil, count: arguments.count)
                for type in types {
                    context.report(
                        SourceDiagnostic(
                            severity: .warning, code: AQLDiagnosticCode.serviceNotFound,
                            message: AQLDiagnosticMessage.serviceNotFound(
                                methodName, for: type, argumentTypes: argumentTypes),
                            range: origin.range))
                }
            }
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

        var arguments = AQLCallArguments(argumentExpressions)
        let argumentValues = try await arguments.values(for: service, in: context)
        return try await service.invoke(
            AQLServiceCall(
                name: methodName, receiver: receiver, arguments: argumentValues, context: context))
    }

    /// Makes the call on one element of a collection receiver.
    ///
    /// The service is looked up for the element. When none matches and the element is an
    /// object, a call without arguments navigates the structural feature of that name. A
    /// service that rejects the types of its arguments with ``AQLExecutionError/typeError(_:)``
    /// counts as missing for the element, as Eclipse AQL finds no service for arguments of
    /// other types.
    ///
    /// - Parameters:
    ///   - element: The element, which is not a collection.
    ///   - arguments: The arguments of the call, evaluated when first needed.
    ///   - context: The context to evaluate in.
    /// - Returns: The result of the call, or ``AQLElementResult/missing`` if the element has
    ///   neither a service nor a feature of the name.
    /// - Throws: Any error raised while evaluating the arguments or by the service.
    @MainActor
    private func call(
        on element: any EcoreValue, arguments: inout AQLCallArguments, in context: AQLExecutionContext
    ) async throws -> AQLElementResult {
        if let service = context.services.find(
            name: methodName, receiver: element, hasReceiver: true, argumentCount: arguments.count)
        {
            let argumentValues = try await arguments.values(for: service, in: context)
            do {
                return .value(
                    try await service.invoke(
                        AQLServiceCall(name: methodName, receiver: element, arguments: argumentValues, context: context)))
            } catch AQLExecutionError.typeError {
                return .missing
            }
        }
        guard element is any EObject, arguments.count == 0 else { return .missing }
        do {
            return .value(try await context.navigate(from: element, property: methodName))
        } catch {
            return .missing
        }
    }

    /// Reports that a dot call on a collection meant the collection's service, if it has one.
    ///
    /// The warning, with the code ``AQLDiagnosticCode/dotCallOnElements`` and the range of the
    /// call, goes to ``AQLExecutionContext/diagnostics``. It is checked for only once an
    /// element of the collection has turned out to lack the service.
    ///
    /// - Parameters:
    ///   - collection: The receiver of the call.
    ///   - argumentCount: The number of arguments of the call.
    ///   - context: The context that collects the warning.
    /// - Returns: Whether the collection has the service, so that the warning was reported.
    @MainActor
    private func warnIfCollectionHasService(
        _ collection: any EcoreValue, argumentCount: Int, in context: AQLExecutionContext
    ) -> Bool {
        guard
            context.services.find(
                name: methodName, receiver: collection, hasReceiver: true, argumentCount: argumentCount) != nil
        else { return false }
        context.report(
            SourceDiagnostic(
                severity: .warning, code: AQLDiagnosticCode.dotCallOnElements,
                message: "'.\(methodName)()' applies to each element of the collection, and an element has no "
                    + "'\(methodName)' service; write '->\(methodName)()' to call the service of the collection",
                range: origin.range))
        return true
    }

    /// The receiver of an arrow call as a collection.
    ///
    /// A collection keeps its kind and a native array becomes a sequence. Any other value
    /// becomes a collection holding just that value, and null an empty collection, of the
    /// kind that ``AQLOptions/singleValueCollections`` names. While
    /// ``AQLOptions/collectionKinds`` is ``AQLCollectionKinds/sequences``, the receiver
    /// becomes a sequence.
    ///
    /// - Parameters:
    ///   - receiver: The evaluated receiver.
    ///   - context: The context whose options apply.
    /// - Returns: The receiver as a collection value.
    @MainActor
    static func arrowReceiver(_ receiver: (any EcoreValue)?, in context: AQLExecutionContext) -> EcoreValueArray {
        let options = context.options
        if options.collectionKinds == .sequences {
            return AQLValues.collection(AQLValues.coerceToCollection(receiver))
        }
        if let collection = receiver as? EcoreValueArray { return collection }
        if let items = AQLValues.elements(of: receiver) { return AQLValues.collection(items) }
        return AQLValues.collection(
            AQLValues.coerceToCollection(receiver), kind: options.singleValueCollections.kind)
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

/// The arguments of a call, evaluated when first needed and then reused.
///
/// A call on each element of a collection evaluates its arguments once, in the form that the
/// service found for an element needs: with bare identifiers resolved to types for a service
/// that ``AQLService/acceptsTypeArguments``, and as plain values otherwise.
struct AQLCallArguments {
    /// The argument expressions.
    let expressions: [any AQLExpression]

    /// The argument values as plain values, once evaluated.
    private var plainValues: [(any EcoreValue)?]?

    /// The argument values with bare identifiers resolved to types, once evaluated.
    private var typedValues: [(any EcoreValue)?]?

    /// Creates the arguments of a call.
    ///
    /// - Parameter expressions: The argument expressions.
    init(_ expressions: [any AQLExpression]) {
        self.expressions = expressions
    }

    /// The number of arguments.
    var count: Int { expressions.count }

    /// The argument values evaluated so far, as plain values if evaluated in that form, or
    /// `nil` if they have not been evaluated.
    var evaluatedValues: [(any EcoreValue)?]? { plainValues ?? typedValues }

    /// The argument values in the form that a service needs.
    ///
    /// - Parameters:
    ///   - service: The service to be called.
    ///   - context: The context to evaluate in.
    /// - Returns: The evaluated arguments.
    /// - Throws: Any error raised while evaluating an argument.
    @MainActor
    mutating func values(for service: AQLService, in context: AQLExecutionContext) async throws
        -> [(any EcoreValue)?]
    {
        if service.acceptsTypeArguments {
            if let typedValues { return typedValues }
            var values: [(any EcoreValue)?] = []
            for expression in expressions {
                if let type = try await Self.typeArgument(expression, in: context) {
                    values.append(type)
                } else {
                    values.append(try await expression.evaluate(in: context))
                }
            }
            typedValues = values
            return values
        }
        if let plainValues { return plainValues }
        var values: [(any EcoreValue)?] = []
        for expression in expressions { values.append(try await expression.evaluate(in: context)) }
        plainValues = values
        return values
    }

    /// Resolves an argument written as a bare identifier to a type descriptor.
    ///
    /// - Parameters:
    ///   - expression: The argument expression.
    ///   - context: The context to evaluate in.
    /// - Returns: The type that the identifier names, or `nil` if the argument is not a bare
    ///   identifier.
    @MainActor
    private static func typeArgument(_ expression: any AQLExpression, in context: AQLExecutionContext)
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
}
