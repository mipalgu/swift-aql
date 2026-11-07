//
//  AQLDropWarningTests.swift
//  AQL
//
//  Created by Rene Hexel on 7/11/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// Services that show the warnings of elements that a dot call leaves out.
private struct DropWarningProbe: AQLServiceProvider {
    var services: [AQLService] {
        [
            AQLService("lengthOf", receiver: .custom { $0 is String || AQLValues.integer($0) != nil }) { call in
                try call.receiverString().count
            },
            AQLService("repeated", receiver: .string, arity: 1) { call in
                String(repeating: try call.receiverString(), count: try call.integer(0))
            },
        ]
    }
}

/// Builds the contexts of the drop warning tests.
@MainActor
enum DropWarningFixture {
    /// Creates a context with the given options and four objects bound.
    ///
    /// `x` and `y` are objects of class `Named` whose `name` is `'n'`, `z` is an object of class
    /// `Other` without a `name` feature, and `w` an object of class `Third` without one.
    ///
    /// - Parameter options: The options of the context.
    /// - Returns: The context.
    static func context(_ options: AQLOptions) -> AQLExecutionContext {
        let context = DotCallFixture.context(options)
        context.setVariable("w", value: DynamicEObject(eClass: EClass(name: "Third")))
        context.register(DropWarningProbe())
        return context
    }

    /// Parses AQL text and evaluates it in a context.
    ///
    /// - Parameters:
    ///   - source: The expression to evaluate.
    ///   - context: The context to evaluate in.
    /// - Returns: The value of the expression and the origin of the parsed expression.
    @discardableResult
    static func evaluate(_ source: String, in context: AQLExecutionContext) async throws
        -> (value: (any EcoreValue)?, origin: SourceOrigin)
    {
        let parsed = AQLParser().parse(source)
        let expression = try #require(parsed.expression, "\(parsed.diagnostics)")
        return (try await expression.evaluate(in: context), expression.origin)
    }

    /// Checks the value and the warnings of an expression.
    ///
    /// - Parameters:
    ///   - source: The expression under test.
    ///   - expected: The expression denoting the expected value.
    ///   - code: The code of every expected warning.
    ///   - messages: The messages of the expected warnings, oldest first.
    ///   - options: The options to evaluate the source with.
    static func check(
        _ source: String, yields expected: String, warns code: String, _ messages: [String],
        with options: AQLOptions = .standard
    ) async throws {
        let context = Self.context(options)
        let (value, origin) = try await evaluate(source, in: context)
        let wanted = try await OptionsFixture.value(of: expected, in: Self.context(.standard))
        #expect(AQLValues.areEqual(value, wanted), "\(source): got \(AQLValues.description(of: value))")
        #expect(OptionsFixture.kinds(value) == OptionsFixture.kinds(wanted), "\(source)")
        #expect(context.diagnostics.map(\.message) == messages, "\(source)")
        for diagnostic in context.diagnostics {
            #expect(diagnostic.severity == .warning)
            #expect(diagnostic.code == code)
            #expect(diagnostic.range != nil)
            #expect(diagnostic.range == origin.range)
        }
    }
}

/// One expression with its value and the messages of the warnings it reports.
struct DropWarningExample: Sendable, CustomTestStringConvertible {
    /// The expression under test.
    let source: String
    /// The expression denoting the expected value.
    let expected: String
    /// The messages of the expected warnings, oldest first.
    let messages: [String]

    init(_ source: String, _ expected: String, _ messages: String...) {
        self.source = source
        self.expected = expected
        self.messages = messages
    }

    var testDescription: String { source }
}

@MainActor
@Suite("AQL warnings for elements left out by dot calls")
struct AQLDropWarningTests {

    // MARK: Features

    /// Navigations over collections some of whose elements lack the feature.
    nonisolated static let featureExamples: [DropWarningExample] = [
        DropWarningExample("Sequence{x, z}.name", "Sequence{'n'}", "Feature name not found in EClass Other"),
        DropWarningExample("Sequence{z, x, z}.name", "Sequence{'n'}", "Feature name not found in EClass Other"),
        DropWarningExample(
            "Sequence{x, z, w, z, w}.name", "Sequence{'n'}",
            "Feature name not found in EClass Other", "Feature name not found in EClass Third"),
        DropWarningExample(
            "OrderedSet{w, Sequence{z}, x}.name", "OrderedSet{'n'}",
            "Feature name not found in EClass Third", "Feature name not found in EClass Other"),
        DropWarningExample(
            "Sequence{x, 'a', 1, y}.name", "Sequence{'n', 'n'}",
            "Attempt to access feature (name) on a value that is not a model object (String)",
            "Attempt to access feature (name) on a value that is not a model object (Integer)"),
        DropWarningExample(
            "Sequence{x, true, 1.5}.name", "Sequence{'n'}",
            "Attempt to access feature (name) on a value that is not a model object (Boolean)",
            "Attempt to access feature (name) on a value that is not a model object (Real)"),
        DropWarningExample("Sequence{z}.name", "Sequence{}", "Feature name not found in EClass Other"),
        DropWarningExample("Sequence{x, z}.label", "Sequence{'l'}", "Feature label not found in EClass Named"),
    ]

    @Test("Navigation warns once for each type of element without the feature", arguments: featureExamples)
    func featureWarnings(_ example: DropWarningExample) async throws {
        try await DropWarningFixture.check(
            example.source, yields: example.expected, warns: AQLDiagnosticCode.featureNotFound, example.messages)
    }

    // MARK: Services

    /// Dot calls on collections some of whose elements have no service of the name.
    nonisolated static let serviceExamples: [DropWarningExample] = [
        DropWarningExample("Sequence{'a', 1}.toUpper()", "Sequence{'A'}", "Couldn't find the 'toUpper(Integer)' service"),
        DropWarningExample(
            "Sequence{1, 'a', 2, true}.toUpper()", "Sequence{'A'}",
            "Couldn't find the 'toUpper(Integer)' service", "Couldn't find the 'toUpper(Boolean)' service"),
        DropWarningExample(
            "Sequence{'a', 1}.repeated(2)", "Sequence{'aa'}", "Couldn't find the 'repeated(Integer,Integer)' service"),
        DropWarningExample("Sequence{'ab', 1}.lengthOf()", "Sequence{2}", "Couldn't find the 'lengthOf(Integer)' service"),
        DropWarningExample(
            "Sequence{'a', 'b'}.repeated('x')", "Sequence{}", "Couldn't find the 'repeated(String,String)' service"),
        DropWarningExample("Sequence{'a', 'b'}.unknown()", "Sequence{}", "Couldn't find the 'unknown(String)' service"),
        DropWarningExample(
            "Sequence{'a', x}.unknown(1, 'b')", "Sequence{}",
            "Couldn't find the 'unknown(String,?,?)' service", "Couldn't find the 'unknown(Named,?,?)' service"),
        DropWarningExample("Sequence{x, z}.name()", "Sequence{'n'}", "Couldn't find the 'name(Other)' service"),
        DropWarningExample(
            "Set{Sequence{z}, x, w}.name()", "Set{'n'}",
            "Couldn't find the 'name(Other)' service", "Couldn't find the 'name(Third)' service"),
    ]

    @Test("A dot call warns once for each type of element without the service", arguments: serviceExamples)
    func serviceWarnings(_ example: DropWarningExample) async throws {
        try await DropWarningFixture.check(
            example.source, yields: example.expected, warns: AQLDiagnosticCode.serviceNotFound, example.messages)
    }

    @Test(
        "A dot call reports only the migration warning when the collection has the service",
        arguments: ["Sequence{1, 2}.size()", "Sequence{'a', 1}.size()", "Sequence{'a', 1}.reportKind()"])
    func migrationWarningOnly(_ source: String) async throws {
        let context = DropWarningFixture.context(.standard)
        try await DropWarningFixture.evaluate(source, in: context)
        #expect(context.diagnostics.map(\.code) == [AQLDiagnosticCode.dotCallOnElements])
    }

    // MARK: No warning

    /// Navigations and dot calls that leave out no element.
    nonisolated static let completeExamples: [String] = [
        "Sequence{x, y}.name", "Sequence{Sequence{x}, OrderedSet{y}}.name", "Sequence{}.name", "Sequence{x, y}.name()",
        "Sequence{'a', 'b'}.toUpper()", "Sequence{'a', 'b'}.vowelOrNull()", "Sequence{z}.label", "x.name", "'a'.size()",
        "Sequence{x, z}->size()", "Sequence{'a', 1}->size()",
    ]

    @Test("Navigation and dot calls that reach every element do not warn", arguments: completeExamples)
    func noWarning(_ source: String) async throws {
        let context = DropWarningFixture.context(.standard)
        try await DropWarningFixture.evaluate(source, in: context)
        #expect(context.diagnostics.isEmpty)
    }

    // MARK: Repetition and ranges

    @Test("Repeated evaluations report each warning once until the diagnostics are cleared")
    func repeatedWarnings() async throws {
        let context = DropWarningFixture.context(.standard)
        let parsed = AQLParser().parse("Sequence{x, z}.name")
        let expression = try #require(parsed.expression)
        for _ in 1...3 { _ = try await expression.evaluate(in: context) }
        #expect(context.diagnostics.count == 1)
        context.clearDiagnostics()
        #expect(context.diagnostics.isEmpty)
        _ = try await expression.evaluate(in: context)
        #expect(context.diagnostics.map(\.code) == [AQLDiagnosticCode.featureNotFound])
    }

    @Test("Each navigation and dot call reports its warning with its own range")
    func separateRanges() async throws {
        let context = DropWarningFixture.context(.standard)
        let source = "Sequence{x, z}.name->size() + Sequence{x, z}.name()->size()"
        try await DropWarningFixture.evaluate(source, in: context)
        #expect(
            context.diagnostics.map(\.code) == [AQLDiagnosticCode.featureNotFound, AQLDiagnosticCode.serviceNotFound])
        let ranges = context.diagnostics.compactMap(\.range)
        #expect(ranges.count == 2)
        #expect(ranges.first != ranges.last)
        let starts = ranges.map(\.start.column)
        #expect(starts.first.map { first in starts.last.map { first < $0 } ?? false } == true)
    }

    @Test("Navigating a collection through the context warns without a range")
    func navigationThroughContext() async throws {
        let context = DropWarningFixture.context(.standard)
        let x = try await context.getVariable("x")
        let z = try await context.getVariable("z")
        let names = try await context.navigate(from: seq(try #require(x), try #require(z)), property: "name")
        #expect(AQLValues.areEqual(names, seq("n")))
        #expect(context.diagnostics.map(\.message) == ["Feature name not found in EClass Other"])
        #expect(context.diagnostics.first?.range == nil)
    }

    // MARK: Strict mode

    @Test(
        "Strict mode warns about the elements it leaves out when some element has the feature or service",
        arguments: [
            DropWarningExample("Sequence{x, z}.name", "Sequence{'n'}", "Feature name not found in EClass Other"),
            DropWarningExample(
                "Sequence{'a', 1}.toUpper()", "Sequence{'A'}", "Couldn't find the 'toUpper(Integer)' service"),
        ])
    func strictPartial(_ example: DropWarningExample) async throws {
        let context = DropWarningFixture.context(AQLOptions(strict: true))
        let (value, _) = try await DropWarningFixture.evaluate(example.source, in: context)
        let wanted = try await OptionsFixture.value(of: example.expected, in: DropWarningFixture.context(.standard))
        #expect(AQLValues.areEqual(value, wanted))
        #expect(context.diagnostics.map(\.message) == example.messages)
    }

    @Test(
        "Strict mode raises only an error when no element has the feature or service",
        arguments: ["Sequence{z}.name", "Sequence{'a'}.name", "Sequence{'a', 'b'}.unknown()", "Sequence{x, z}.unknown()"])
    func strictRejects(_ source: String) async throws {
        let context = DropWarningFixture.context(AQLOptions(strict: true))
        await #expect(throws: AQLExecutionError.self) {
            try await DropWarningFixture.evaluate(source, in: context)
        }
        #expect(context.diagnostics.isEmpty)
    }

    // MARK: Legacy mode

    @Test(
        "Dot calls on the collection do not warn",
        arguments: [AQLOptions.legacy, AQLOptions(dotCalls: .collection)])
    func legacy(_ options: AQLOptions) async throws {
        let context = DropWarningFixture.context(options)
        let (names, _) = try await DropWarningFixture.evaluate("Sequence{x, 'a', 1, y}.name", in: context)
        #expect(AQLValues.areEqual(names, seq("n", "n")))
        await #expect(throws: (any Error).self) {
            try await DropWarningFixture.evaluate("Sequence{x, z}.name", in: context)
        }
        await #expect(throws: (any Error).self) {
            try await DropWarningFixture.evaluate("Sequence{'a', 1}.toUpper()", in: context)
        }
        #expect(context.diagnostics.isEmpty)
    }
}
