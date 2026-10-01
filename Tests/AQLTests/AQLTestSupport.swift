//
//  AQLTestSupport.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// One parameterised library call: `receiver.method(args)` should produce `expected`.
struct LibraryCase: Sendable, CustomTestStringConvertible {
    let receiver: (any EcoreValue)?
    let method: String
    let arguments: [any EcoreValue]
    let expected: (any EcoreValue)?
    let arrow: Bool

    init(
        _ receiver: (any EcoreValue)?, _ method: String, _ arguments: any EcoreValue...,
        expect expected: (any EcoreValue)?, arrow: Bool = false
    ) {
        self.receiver = receiver
        self.method = method
        self.arguments = arguments
        self.expected = expected
        self.arrow = arrow
    }

    var testDescription: String {
        "\(AQLValues.description(of: receiver)).\(method)(\(arguments.map { AQLValues.description(of: $0) }.joined(separator: ", "))) = \(AQLValues.description(of: expected))"
    }
}

/// Builds a collection value.
func seq(_ values: any EcoreValue...) -> EcoreValueArray { EcoreValueArray(values) }

/// A literal expression.
func lit(_ value: (any EcoreValue)?) -> AQLLiteralExpression { AQLLiteralExpression(value: value) }

/// Creates a context with an empty engine.
@MainActor
func makeContext() -> AQLExecutionContext {
    AQLExecutionContext(executionEngine: ECoreExecutionEngine(models: [:]))
}

/// Evaluates a library case in a fresh context.
@MainActor
func evaluate(_ test: LibraryCase, in context: AQLExecutionContext = makeContext()) async throws
    -> (any EcoreValue)?
{
    try await AQLCallExpression(
        source: lit(test.receiver), methodName: test.method,
        arguments: test.arguments.map { lit($0) }, usesArrow: test.arrow
    ).evaluate(in: context)
}

/// Checks a library case.
@MainActor
func check(_ test: LibraryCase) async throws {
    let result = try await evaluate(test)
    #expect(AQLValues.areEqual(result, test.expected), "got \(AQLValues.description(of: result))")
}
