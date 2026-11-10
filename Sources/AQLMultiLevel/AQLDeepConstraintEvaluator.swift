//
//  AQLDeepConstraintEvaluator.swift
//  AQLMultiLevel
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
public import AQL
public import ECore
public import EMFBase
public import MultiLevel

/// Errors raised when a deep constraint cannot be evaluated as AQL.
public enum AQLMultiLevelError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The body of a constraint is not a valid AQL expression; EOL bodies are not supported.
    ///
    /// The associated values are the name of the constraint and the parser's messages.
    case notAQL(String, [String])

    /// The body of a constraint does not evaluate to a Boolean.
    ///
    /// The associated value is the name of the constraint.
    case notBoolean(String)

    /// A sentence that describes the error.
    public var description: String {
        switch self {
        case .notAQL(let name, let messages):
            return "the body of '\(name)' is not valid AQL (EOL bodies are not supported): "
                + messages.joined(separator: "; ")
        case .notBoolean(let name):
            return "the body of '\(name)' does not evaluate to a Boolean"
        }
    }
}

/// Evaluates deep constraints written in AQL.
///
/// A body is evaluated against the deep level view of its evaluation level: `self` is the
/// object of the constrained clabject, every class of the view is bound to a variable of its
/// name so that `ProductType.allInstances()` yields the deep instances at that level, and
/// the deep services of ``AQLMultiLevelServices`` are available. The views of every level
/// are registered with the execution engine, so references across levels resolve. A body
/// that is not valid AQL, such as an EOL body, is reported rather than reinterpreted.
///
/// ```swift
/// let diagnostics = await model.validate(evaluator: AQLDeepConstraintEvaluator())
/// ```
public struct AQLDeepConstraintEvaluator: DeepConstraintEvaluator {
    /// The options with which bodies are evaluated.
    public let options: AQLOptions

    /// Creates the evaluator.
    ///
    /// - Parameter options: The options with which bodies are evaluated (default
    ///   ``AQL/AQLOptions/standard``).
    public init(options: AQLOptions = .standard) {
        self.options = options
    }

    /// The alias under which the view of a level is registered with the engine.
    static func alias(of view: DeepLevelView) -> String { "\(view.package.name)\(view.level)" }

    /// Evaluates a constraint.
    ///
    /// - Parameter context: The constraint, its `self` object and its views.
    /// - Returns: The value of the body.
    /// - Throws: ``AQLMultiLevelError`` if the body is not valid AQL or not Boolean, or the
    ///   error of the evaluation.
    public func evaluate(_ context: DeepConstraintContext) async throws -> Bool {
        let parsed = AQLParser().parse(context.constraint.body)
        let errors = parsed.diagnostics.filter { $0.severity == .error }
        guard errors.isEmpty, let expression = parsed.expression else {
            throw AQLMultiLevelError.notAQL(context.constraint.name, errors.map(\.message))
        }
        let engine = ECoreExecutionEngine(models: [:])
        for view in context.views { await engine.registerResource(view.resource, alias: Self.alias(of: view)) }
        let value = try await Self.evaluate(expression, context: context, engine: engine, options: options)
        guard let result = value as? Bool else { throw AQLMultiLevelError.notBoolean(context.constraint.name) }
        return result
    }

    /// Evaluates a parsed body on the main actor.
    @MainActor
    static func evaluate(
        _ expression: any AQLExpression, context: DeepConstraintContext, engine: ECoreExecutionEngine,
        options: AQLOptions
    ) async throws -> (any EcoreValue)? {
        let aql = AQLExecutionContext(
            executionEngine: engine, options: options, serviceProviders: [AQLMultiLevelServices(views: context.views)])
        aql.addResource(context.view.resource)
        for classifier in context.view.package.eClassifiers {
            aql.setGlobalVariable(classifier.name, value: AQLTypeDescriptor(typeName: classifier.name))
        }
        if let object = context.object { aql.setVariable(AQLMultiLevelSyntax.selfVariable, value: object) }
        return try await expression.evaluate(in: aql)
    }
}

/// The vocabulary of AQL bodies of deep constraints.
public enum AQLMultiLevelSyntax {
    /// The variable that denotes the constrained object.
    public static let selfVariable = "self"
}
