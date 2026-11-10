//
//  AQLDotCallTests.swift
//  AQL
//
//  Created by Rene Hexel on 7/11/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// Services that show how a dot call collects the results of the elements of a collection.
private struct DotCallProbe: AQLServiceProvider {
    var services: [AQLService] {
        [
            AQLService("twice", receiver: .string) { call in
                let text = try call.receiverString()
                return EcoreValueArray([text, text])
            },
            AQLService("vowelOrNull", receiver: .string) { call in
                let text = try call.receiverString()
                return "aeiou".contains(text) ? text : nil
            },
            AQLService("reportKind", receiver: .collection) { call in call.receiverKind.rawValue },
        ]
    }
}

/// Builds the contexts of the dot call tests.
@MainActor
enum DotCallFixture {
    /// Creates a context with the given options, the probe services and three objects bound.
    ///
    /// `x` and `y` are objects of class `Named` whose `name` is `'n'`, and `z` is an object of
    /// class `Other` whose `label` is `'l'` and that has no `name` feature.
    ///
    /// - Parameter options: The options of the context.
    /// - Returns: The context.
    static func context(_ options: AQLOptions) -> AQLExecutionContext {
        let context = OptionsFixture.context(options)
        var other = EClass(name: "Other")
        other.eStructuralFeatures.append(EAttribute(name: "label", eType: EDataType(name: "EString")))
        var object = DynamicEObject(eClass: other)
        object.eSet("label", value: "l")
        context.setVariable("z", value: object)
        context.register(DotCallProbe())
        return context
    }

    /// Checks that a source yields the value of an expected expression, kinds included.
    ///
    /// - Parameters:
    ///   - source: The expression under test.
    ///   - expected: The expression denoting the expected value.
    ///   - options: The options to evaluate the source with.
    static func check(_ source: String, yields expected: String, with options: AQLOptions) async throws {
        let result = try await OptionsFixture.value(of: source, in: context(options))
        let wanted = try await OptionsFixture.value(of: expected, in: context(.standard))
        #expect(AQLValues.areEqual(result, wanted), "\(source): got \(AQLValues.description(of: result))")
        #expect(OptionsFixture.kinds(result) == OptionsFixture.kinds(wanted), "\(source)")
    }
}

@MainActor
@Suite("AQL dot calls on collections")
struct AQLDotCallTests {

    // MARK: Options

    @Test("The dot call option has two cases spelt as on the command line")
    func spellings() {
        #expect(AQLDotCalls.allCases.map(\.rawValue) == ["each-element", "collection"])
        #expect(AQLDotCalls(rawValue: "each-element") == .eachElement)
        #expect(AQLDotCalls(rawValue: "collection") == .collection)
        #expect(AQLDotCalls(rawValue: "eachElement") == nil)
    }

    @Test("Dot calls apply to each element by default and to the collection in legacy mode")
    func presets() {
        #expect(AQLOptions().dotCalls == .eachElement)
        #expect(AQLOptions.standard.dotCalls == .eachElement)
        #expect(AQLOptions.legacy.dotCalls == .collection)
        #expect(AQLOptions(dotCalls: .collection) != .standard)
        #expect(AQLOptions(semantics: .legacy).dotCalls == .collection)
        var options = AQLOptions.standard
        options.dotCalls = .collection
        #expect(options == AQLOptions(dotCalls: .collection))
        #expect(Set([AQLOptions(dotCalls: .collection), AQLOptions(dotCalls: .collection)]).count == 1)
    }

    // MARK: Each element

    /// Dot calls on collections with the values that Eclipse AQL computes for them.
    nonisolated static let eachElementExamples: [KindExample] = [
        KindExample("Sequence{'a', 'b'}.size()", "Sequence{1, 1}"),
        KindExample("Sequence{'a', 'bc'}.size()", "Sequence{1, 2}"),
        KindExample("Sequence{'a', 'b'}.toUpper()", "Sequence{'A', 'B'}"),
        KindExample("OrderedSet{'ab', 'c'}.size()", "OrderedSet{2, 1}"),
        KindExample("OrderedSet{'a', 'b'}.size()", "OrderedSet{1}"),
        KindExample("Set{'a', 'bc', 'd'}.size()", "Set{1, 2}"),
        KindExample("Bag{'a', 'b'}.size()", "Bag{1, 1}"),
        KindExample("Sequence{1, 2}.size()", "Sequence{}"),
        KindExample("Sequence{}.size()", "Sequence{}"),
        KindExample("Sequence{Sequence{'a'}, Sequence{'b', 'c'}}.size()", "Sequence{1, 1, 1}"),
        KindExample("Sequence{OrderedSet{'a', 'b'}, 'cd'}.size()", "Sequence{1, 2}"),
        KindExample("OrderedSet{Sequence{'a', 'b'}}.size()", "OrderedSet{1}"),
        KindExample("Sequence{'a', null, 'b'}.toUpper()", "Sequence{'A', 'B'}"),
        KindExample("Sequence{'a', 1, 'b'}.toUpper()", "Sequence{'A', 'B'}"),
        KindExample("Sequence{'a', 'b'}.concat('x')", "Sequence{'ax', 'bx'}"),
        KindExample("Sequence{'a', 'b', 'c'}.concat(Sequence{'d', 'e'})", "Sequence{}"),
        KindExample("Sequence{'a', 'b'}.concat(null)", "Sequence{'a', 'b'}"),
        KindExample("OrderedSet{'a', 'b'}.add(Sequence{'c'})", "OrderedSet{'ac', 'bc'}"),
        KindExample("Sequence{'a', 'A'}.toUpper()", "Sequence{'A', 'A'}"),
        KindExample("OrderedSet{'a', 'A'}.toUpper()", "OrderedSet{'A'}"),
        KindExample("Sequence{1, 2, Sequence{3, 4}}.toString()", "Sequence{'1', '2', '3', '4'}"),
        KindExample("Sequence{1, 2}.toString().size()", "Sequence{1, 1}"),
        KindExample("Sequence{'a', 1}.oclIsKindOf(String)", "Sequence{true, false}"),
        KindExample("Sequence{'a', 'b'}.twice()", "Sequence{'a', 'a', 'b', 'b'}"),
        KindExample("OrderedSet{'a', 'b'}.twice()", "OrderedSet{'a', 'b'}"),
        KindExample("Sequence{'a', 'b', 'e'}.vowelOrNull()", "Sequence{'a', 'e'}"),
        KindExample("Sequence{'a', 'b'}.reportKind()", "Sequence{}"),
        KindExample("Sequence{x, y}.name()", "Sequence{'n', 'n'}"),
        KindExample("Sequence{x, z}.name()", "Sequence{'n'}"),
    ]

    @Test("A dot call on a collection applies to each element", arguments: eachElementExamples)
    func eachElement(_ example: KindExample) async throws {
        try await DotCallFixture.check(example.source, yields: example.expected, with: .standard)
    }

    /// Collection service examples that the Acceleo documentation writes with a dot, with the
    /// values that Eclipse AQL computes for them: no string has these services for arguments
    /// that are collections.
    nonisolated static let documentationExamples: [KindExample] = [
        KindExample("OrderedSet{'a', 'b', 'c'}.concat(Sequence{'d', 'e'})", "OrderedSet{}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.addAll(Sequence{'d', 'e'})", "OrderedSet{}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.addAll(OrderedSet{'c', 'b', 'f'})", "OrderedSet{}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.removeAll(OrderedSet{'c', 'b', 'f'})", "OrderedSet{}"),
        KindExample("Set{'a', 'b', 'c'}.concat(Sequence{'d', 'e'})", "Set{}"),
        KindExample("Sequence{'a', 'b', 'c'}.addAll(OrderedSet{'c', 'e'})", "Sequence{}"),
        KindExample("Sequence{'a', 'b', 'c'}.removeAll(OrderedSet{'c', 'b', 'f'})", "Sequence{}"),
        KindExample("Bag{'a', 'b', 'c'}.addAll(OrderedSet{'c', 'e'})", "Bag{}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.including('b')", "OrderedSet{}"),
    ]

    @Test("Collection service examples written with a dot apply to each element", arguments: documentationExamples)
    func documentationExample(_ example: KindExample) async throws {
        try await DotCallFixture.check(example.source, yields: example.expected, with: .standard)
    }

    /// Calls whose value does not depend on the dot call option.
    nonisolated static let unaffectedExamples: [KindExample] = [
        KindExample("Sequence{'a', 'b'}->size()", "2"),
        KindExample("OrderedSet{'a', 'b'}->size()", "2"),
        KindExample("'a'->size()", "1"),
        KindExample("null->size()", "0"),
        KindExample("'ab'.size()", "2"),
        KindExample("'ab'.toUpper()", "'AB'"),
        KindExample("x.name()", "'n'"),
        KindExample("Sequence{'a'} + Sequence{'b'}", "Sequence{'a', 'b'}"),
        KindExample("Sequence{'a', 'b'}->reportKind()", "'Sequence'"),
        KindExample("size(Sequence{'a', 'b'})", "2"),
    ]

    @Test(
        "Arrow calls, operators and calls on single values ignore the dot call option",
        arguments: unaffectedExamples, [AQLDotCalls.eachElement, .collection])
    func unaffected(_ example: KindExample, _ dotCalls: AQLDotCalls) async throws {
        try await DotCallFixture.check(example.source, yields: example.expected, with: AQLOptions(dotCalls: dotCalls))
    }

    // MARK: Collection

    /// Dot calls on collections with the values that they have in version 0.6, when the
    /// collection kinds are kept.
    nonisolated static let collectionExamples: [KindExample] = [
        KindExample("Sequence{'a', 'b'}.size()", "2"),
        KindExample("OrderedSet{'ab', 'c'}.size()", "2"),
        KindExample("Sequence{1, 2}.size()", "2"),
        KindExample("Sequence{1, 2}.toString().size()", "2"),
        KindExample("Sequence{'a', 'b'}.concat('x')", "Sequence{'a', 'b', 'x'}"),
        KindExample("Sequence{'a', 'b'}.reportKind()", "'Sequence'"),
        KindExample("OrderedSet{'a', 'b'}.reportKind()", "'OrderedSet'"),
    ]

    @Test("A dot call applies to the collection when the option says so", arguments: collectionExamples)
    func collection(_ example: KindExample) async throws {
        try await DotCallFixture.check(example.source, yields: example.expected, with: AQLOptions(dotCalls: .collection))
    }

    @Test("A dot call applies to the collection under the legacy options")
    func legacy() async throws {
        let context = DotCallFixture.context(.legacy)
        #expect(try await OptionsFixture.value(of: "Sequence{'a', 'b'}.size()", in: context) as? Int == 2)
        #expect(try await OptionsFixture.value(of: "Sequence{1, 2}.size()", in: context) as? Int == 2)
        let text = try await OptionsFixture.value(of: "Sequence{1, 2}.toString()", in: context)
        #expect(text as? String == "[1, 2]")
    }

    // MARK: Navigation

    /// Navigations over collections under the standard options.
    nonisolated static let navigationExamples: [KindExample] = [
        KindExample("Sequence{x, y}.name", "Sequence{'n', 'n'}"),
        KindExample("OrderedSet{x, y}.name", "OrderedSet{'n'}"),
        KindExample("Set{x, y}.name", "Set{'n'}"),
        KindExample("Sequence{x, 'a', y}.name", "Sequence{'n', 'n'}"),
        KindExample("Sequence{Sequence{x}, OrderedSet{y, x}}.name", "Sequence{'n', 'n'}"),
        KindExample("Sequence{x, z}.name", "Sequence{'n'}"),
        KindExample("Sequence{x, z}.label", "Sequence{'l'}"),
        KindExample("Sequence{z, z}.name", "Sequence{}"),
        KindExample("Sequence{}.name", "Sequence{}"),
    ]

    @Test("Navigation over a collection leaves out elements without the feature", arguments: navigationExamples)
    func navigation(_ example: KindExample) async throws {
        try await DotCallFixture.check(example.source, yields: example.expected, with: .standard)
    }

    @Test(
        "Navigation over a collection fails for an object without the feature when dot calls apply to the collection",
        arguments: [AQLOptions.legacy, AQLOptions(dotCalls: .collection)])
    func navigationToMissingFeature(_ options: AQLOptions) async throws {
        let context = DotCallFixture.context(options)
        await #expect(throws: (any Error).self) {
            _ = try await OptionsFixture.value(of: "Sequence{x, z}.name", in: context)
        }
        let names = try await OptionsFixture.value(of: "Sequence{x, 'a', y}.name", in: context)
        #expect(AQLValues.areEqual(names, seq("n", "n")))
    }

    // MARK: Strict mode

    /// Dot calls and navigations over collections none of whose elements has the service or
    /// the feature.
    nonisolated static let missingEverywhere: [String] = [
        "Sequence{1, 2}.size()",
        "Sequence{Sequence{1}, OrderedSet{2}}.size()",
        "Sequence{'a', 'b'}.reportKind()",
        "Sequence{'a', 'b'}.unknown()",
        "Sequence{'a', 'b'}.concat(Sequence{'c'})",
        "Sequence{x, y}.unknown()",
        "Sequence{z}.name",
        "Sequence{'a'}.name",
        "Sequence{'a', 'b'}.reportKind",
    ]

    @Test("Strict mode rejects a dot call that no element of the collection has", arguments: missingEverywhere)
    func strictRejects(_ source: String) async throws {
        let context = DotCallFixture.context(AQLOptions(strict: true))
        await #expect(throws: AQLExecutionError.self) {
            _ = try await OptionsFixture.value(of: source, in: context)
        }
    }

    @Test("Outside strict mode the elements without the service are left out", arguments: missingEverywhere)
    func lenientDrops(_ source: String) async throws {
        try await DotCallFixture.check(source, yields: "Sequence{}", with: .standard)
    }

    /// Dot calls that strict mode accepts, with their values.
    nonisolated static let strictAccepted: [KindExample] = [
        KindExample("Sequence{'a', 1}.toUpper()", "Sequence{'A'}"),
        KindExample("Sequence{}.size()", "Sequence{}"),
        KindExample("Sequence{Sequence{}}.size()", "Sequence{}"),
        KindExample("Sequence{'a', 'b'}.vowelOrNull()", "Sequence{'a'}"),
        KindExample("Sequence{x, z}.name", "Sequence{'n'}"),
        KindExample("Sequence{}.name", "Sequence{}"),
    ]

    @Test("Strict mode accepts a dot call that some element of the collection has", arguments: strictAccepted)
    func strictAccepts(_ example: KindExample) async throws {
        try await DotCallFixture.check(example.source, yields: example.expected, with: AQLOptions(strict: true))
    }

    @Test("Strict mode accepts a dot call on the collection when dot calls apply to the collection")
    func strictCollection() async throws {
        try await DotCallFixture.check(
            "Sequence{1, 2}.size()", yields: "2", with: AQLOptions(dotCalls: .collection, strict: true))
    }

    // MARK: Migration warnings

    /// Parses AQL text, evaluates it in a context and returns the origin of the expression.
    ///
    /// - Parameters:
    ///   - source: The expression to evaluate.
    ///   - context: The context to evaluate in.
    /// - Returns: The origin of the parsed expression.
    @discardableResult
    static func evaluate(_ source: String, in context: AQLExecutionContext) async throws -> SourceOrigin {
        let parsed = AQLParser().parse(source)
        let expression = try #require(parsed.expression, "\(parsed.diagnostics)")
        _ = try await expression.evaluate(in: context)
        return expression.origin
    }

    @Test("A new context has no diagnostics")
    func noDiagnostics() {
        #expect(DotCallFixture.context(.standard).diagnostics.isEmpty)
    }

    @Test(
        "A dot call warns when an element lacks a service that the collection has",
        arguments: ["Sequence{1, 2}.size()", "Sequence{'a', 1}.size()", "OrderedSet{Sequence{1}}.size()"])
    func migrationWarning(_ source: String) async throws {
        let context = DotCallFixture.context(.standard)
        let origin = try await Self.evaluate(source, in: context)
        #expect(context.diagnostics.count == 1)
        let diagnostic = try #require(context.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.code == AQLDiagnosticCode.dotCallOnElements)
        #expect(diagnostic.message.contains("size"))
        #expect(diagnostic.range != nil)
        #expect(diagnostic.range == origin.range)
    }

    @Test(
        "A dot call does not warn when every element has the service or the collection has none",
        arguments: [
            "Sequence{'a', 'b'}.size()", "Sequence{'a', 1}.toUpper()", "Sequence{}.size()", "Sequence{'a'}->size()",
            "Sequence{x, z}.name", "Sequence{z}.name()", "'a'.size()",
        ])
    func noMigrationWarning(_ source: String) async throws {
        let context = DotCallFixture.context(.standard)
        try await Self.evaluate(source, in: context)
        #expect(!context.diagnostics.contains { $0.code == AQLDiagnosticCode.dotCallOnElements })
    }

    @Test(
        "A dot call on the collection does not warn",
        arguments: [AQLOptions.legacy, AQLOptions(dotCalls: .collection)])
    func noWarningOnCollection(_ options: AQLOptions) async throws {
        let context = DotCallFixture.context(options)
        try await Self.evaluate("Sequence{1, 2}.size()", in: context)
        #expect(context.diagnostics.isEmpty)
    }

    @Test("Repeated evaluations report a warning once until the diagnostics are cleared")
    func repeatedWarnings() async throws {
        let context = DotCallFixture.context(.standard)
        let parsed = AQLParser().parse("Sequence{1, 2}.size()")
        let expression = try #require(parsed.expression)
        for _ in 1...3 { _ = try await expression.evaluate(in: context) }
        #expect(context.diagnostics.count == 1)
        try await Self.evaluate("Sequence{1}.reportKind()", in: context)
        #expect(context.diagnostics.count == 2)
        #expect(Set(context.diagnostics.map(\.message)).count == 2)
        context.clearDiagnostics()
        #expect(context.diagnostics.isEmpty)
        _ = try await expression.evaluate(in: context)
        #expect(context.diagnostics.count == 1)
    }

    @Test("Strict mode keeps the warning of a dot call that it rejects")
    func strictWarning() async throws {
        let context = DotCallFixture.context(AQLOptions(strict: true))
        await #expect(throws: AQLExecutionError.self) {
            try await Self.evaluate("Sequence{1, 2}.size()", in: context)
        }
        #expect(context.diagnostics.map(\.code) == [AQLDiagnosticCode.dotCallOnElements])
    }
}
