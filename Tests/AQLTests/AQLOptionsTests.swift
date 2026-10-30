//
//  AQLOptionsTests.swift
//  AQL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// An AQL expression with its expected values under the legacy and the standard options.
///
/// The legacy values are those that version 0.6.1 computes for the expression.
struct CompatibilityExample: Sendable, CustomTestStringConvertible {
    /// The expression under test.
    let source: String
    /// The expression denoting the value under ``AQLOptions/legacy``, where every collection is a sequence.
    let legacy: String
    /// The expression denoting the value, including its collection kind, under ``AQLOptions/standard``.
    let standard: String

    init(_ source: String, legacy: String, standard: String) {
        self.source = source
        self.legacy = legacy
        self.standard = standard
    }

    /// An example whose value is the same under both options.
    init(_ source: String, both: String) {
        self.init(source, legacy: both, standard: both)
    }

    var testDescription: String { source }
}

/// Builds the contexts and objects of the option tests.
@MainActor
enum OptionsFixture {
    /// The variables bound to two objects whose `name` features are both `'n'`.
    static let objectVariables = ["x", "y"]

    /// Creates a context with the given options and two named objects bound.
    ///
    /// - Parameter options: The options of the context.
    /// - Returns: The context.
    static func context(_ options: AQLOptions) -> AQLExecutionContext {
        var eClass = EClass(name: "Named")
        eClass.eStructuralFeatures.append(EAttribute(name: "name", eType: EDataType(name: "EString")))
        let context = makeContext(options: options)
        for variable in objectVariables {
            var object = DynamicEObject(eClass: eClass)
            object.eSet("name", value: "n")
            context.setVariable(variable, value: object)
        }
        return context
    }

    /// Parses and evaluates AQL text in the given context.
    static func value(of source: String, in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let parsed = AQLParser().parse(source)
        let expression = try #require(parsed.expression, "\(parsed.diagnostics)")
        return try await expression.evaluate(in: context)
    }

    /// The kinds of a value and of every collection nested in it, outermost first.
    static func kinds(_ value: (any EcoreValue)?) -> [EcoreCollectionKind] {
        guard let array = value as? EcoreValueArray else { return [] }
        return [array.kind] + array.values.flatMap(kinds)
    }

    /// Checks that a source yields the value of an expected expression, kinds included.
    ///
    /// - Parameters:
    ///   - source: The expression under test.
    ///   - expected: The expression denoting the expected value.
    ///   - options: The options to evaluate the source with.
    ///   - expectedKinds: The kinds expected for the result and its nested collections,
    ///     or nil to take them from the expected value under the standard options.
    static func check(
        _ source: String, yields expected: String, with options: AQLOptions,
        kinds expectedKinds: [EcoreCollectionKind]? = nil
    ) async throws {
        let result = try await value(of: source, in: context(options))
        let wanted = try await value(of: expected, in: context(.standard))
        #expect(AQLValues.areEqual(result, wanted), "\(source): got \(AQLValues.description(of: result))")
        #expect(kinds(result) == (expectedKinds ?? kinds(wanted)), "\(source)")
    }
}

@MainActor
@Suite("AQL options")
struct AQLOptionsTests {

    // MARK: Options values

    @Test("The standard options are the defaults")
    func standardOptions() {
        let options = AQLOptions()
        #expect(options == .standard)
        #expect(options.collectionArguments == .whole)
        #expect(options.collectionKinds == .distinguished)
        #expect(options.singleValueCollections == .set)
        #expect(options.containerLookup == .resources)
    }

    @Test("The legacy options select the behaviour of version 0.6")
    func legacyOptions() {
        let options = AQLOptions.legacy
        #expect(options.collectionArguments == .firstElement)
        #expect(options.collectionKinds == .sequences)
        #expect(options.singleValueCollections == .sequence)
        #expect(options.containerLookup == .registeredObjects)
        #expect(options != .standard)
        #expect(
            options
                == AQLOptions(
                    collectionArguments: .firstElement, collectionKinds: .sequences,
                    singleValueCollections: .sequence, containerLookup: .registeredObjects))
    }

    @Test("Options can be changed one at a time")
    func optionsAreIndependent() {
        var options = AQLOptions.standard
        options.collectionArguments = .firstElement
        #expect(options == AQLOptions(collectionArguments: .firstElement))
        options.collectionKinds = .sequences
        options.singleValueCollections = .sequence
        options.containerLookup = .registeredObjects
        #expect(options == .legacy)
        #expect(Set([AQLOptions.standard, .legacy, AQLOptions()]).count == 2)
    }

    @Test("Each option has two cases spelt as on the command line")
    func commandLineSpellings() {
        #expect(AQLCollectionArguments.allCases.map(\.rawValue) == ["whole", "first-element"])
        #expect(AQLCollectionKinds.allCases.map(\.rawValue) == ["distinguished", "sequences"])
        #expect(AQLSingleValueCollections.allCases.map(\.rawValue) == ["set", "sequence"])
        #expect(AQLContainerLookup.allCases.map(\.rawValue) == ["resources", "registered-objects"])
        #expect(AQLCollectionArguments(rawValue: "first-element") == .firstElement)
        #expect(AQLContainerLookup(rawValue: "registered-objects") == .registeredObjects)
        #expect(AQLCollectionKinds(rawValue: "Sequences") == nil)
    }

    // MARK: Source compatibility

    @Test("Collection literal kinds keep the cases and raw values of version 0.6")
    func literalKindRawValues() {
        let kinds: [AQLCollectionLiteralExpression.Kind] = [.sequence, .orderedSet, .set, .bag]
        #expect(kinds.map(\.rawValue) == ["Sequence", "OrderedSet", "Set", "Bag"])
        #expect(kinds.allSatisfy { AQLCollectionLiteralExpression.Kind(rawValue: $0.rawValue) == $0 })
        #expect(Set(kinds).count == kinds.count)
    }

    // MARK: Contexts

    @Test("The initialisers of version 0.6 create legacy contexts")
    func earlierInitialisersAreLegacy() {
        #expect(AQLExecutionContext().options == .legacy)
        #expect(AQLExecutionContext(unsetFeatureReads: .undefined).options == .legacy)
        #expect(AQLExecutionContext(executionEngine: ECoreExecutionEngine(models: [:])).options == .legacy)
        #expect(makeContext().options == .legacy)
    }

    @Test("The initialisers with options keep the options", arguments: [AQLOptions.standard, .legacy])
    func initialisersKeepOptions(_ options: AQLOptions) async {
        let engine = ECoreExecutionEngine(models: [:])
        #expect(AQLExecutionContext(executionEngine: engine, options: options).options == options)
        let own = AQLExecutionContext(options: options)
        #expect(own.options == options)
        #expect(await own.executionEngine.unsetFeatureReads == .defaults)
        let undefined = AQLExecutionContext(options: options, unsetFeatureReads: .undefined)
        #expect(undefined.options == options)
        #expect(await undefined.executionEngine.unsetFeatureReads == .undefined)
    }

    @Test("The initialisers with options register service providers")
    func initialisersRegisterProviders() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let contexts = [
            AQLExecutionContext(executionEngine: engine, options: .standard, serviceProviders: [KindReporter()]),
            AQLExecutionContext(options: .standard, serviceProviders: [KindReporter()]),
        ]
        for context in contexts {
            let result = try await OptionsFixture.value(of: "Bag{1}.reportKind()", in: context)
            #expect(result as? String == EcoreCollectionKind.bag.rawValue)
        }
    }

    @Test("A context's options can be changed")
    func changingOptions() async throws {
        let context = makeContext()
        context.options = .standard
        let result = try await OptionsFixture.value(of: "'a'->including('a')", in: context)
        #expect(OptionsFixture.kinds(result) == [.set])
    }

    // MARK: Behaviour under both presets

    /// Adding a collection argument with `including`, `append` and `prepend`.
    nonisolated static let collectionArgumentExamples: [CompatibilityExample] = [
        .init(
            "Sequence{'a', 'b', 'c'}->including(Sequence{'d', 'e'})",
            legacy: "Sequence{'a', 'b', 'c', 'd'}", standard: "Sequence{'a', 'b', 'c', Sequence{'d', 'e'}}"),
        .init(
            "Sequence{'a', 'b', 'c'}->append(Sequence{'d', 'e'})",
            legacy: "Sequence{'a', 'b', 'c', 'd'}", standard: "Sequence{'a', 'b', 'c', Sequence{'d', 'e'}}"),
        .init(
            "Sequence{'a', 'b', 'c'}->prepend(Sequence{'d', 'e'})",
            legacy: "Sequence{'d', 'a', 'b', 'c'}", standard: "Sequence{Sequence{'d', 'e'}, 'a', 'b', 'c'}"),
        .init(
            "Sequence{'a', 'b', 'c'}.including(OrderedSet{'d', 'e'})",
            legacy: "Sequence{'a', 'b', 'c', 'd'}", standard: "Sequence{'a', 'b', 'c', OrderedSet{'d', 'e'}}"),
        .init("Sequence{'a'}->append(Sequence{})", legacy: "Sequence{'a'}", standard: "Sequence{'a', Sequence{}}"),
        .init("Sequence{'a'}->prepend(Sequence{})", legacy: "Sequence{'a'}", standard: "Sequence{Sequence{}, 'a'}"),
        .init("Sequence{'a'}->including(Sequence{})", legacy: "Sequence{'a'}", standard: "Sequence{'a', Sequence{}}"),
        .init("Sequence{'a'}->append(null)", both: "Sequence{'a'}"),
        .init(
            "Sequence{'a', 'b', 'c'}->insertAt(2, Sequence{'d', 'e'})",
            both: "Sequence{'a', Sequence{'d', 'e'}, 'b', 'c'}"),
        .init(
            "OrderedSet{'a', 'b'}->append(OrderedSet{'b', 'c'})",
            legacy: "Sequence{'a', 'b', 'b'}", standard: "OrderedSet{'a', 'b', OrderedSet{'b', 'c'}}"),
    ]

    /// Collection kinds, elements already present and the kinds of results.
    nonisolated static let collectionKindExamples: [CompatibilityExample] = [
        .init("OrderedSet{'a', 'b', 'c'}->append('b')", legacy: "Sequence{'a', 'b', 'c', 'b'}", standard: "OrderedSet{'a', 'c', 'b'}"),
        .init("OrderedSet{'a', 'b', 'c'}->prepend('b')", legacy: "Sequence{'b', 'a', 'b', 'c'}", standard: "OrderedSet{'b', 'a', 'c'}"),
        .init("OrderedSet{'a', 'b', 'c'}->including('b')", legacy: "Sequence{'a', 'b', 'c', 'b'}", standard: "OrderedSet{'a', 'b', 'c'}"),
        .init("Set{'a', 'b'}->including('a')", legacy: "Sequence{'a', 'b', 'a'}", standard: "Set{'a', 'b'}"),
        .init("OrderedSet{1, 2, 3}->insertAt(1, 3)", legacy: "Sequence{3, 1, 2, 3}", standard: "OrderedSet{3, 1, 2}"),
        .init("OrderedSet{1, 2, 3}->insertAt(4, 1)", legacy: "Sequence{1, 2, 3, 1}", standard: "OrderedSet{2, 3, 1}"),
        .init(
            "OrderedSet{'a', 'b'}->concat(Sequence{'b', 'c', 'c'})",
            legacy: "Sequence{'a', 'b', 'b', 'c', 'c'}", standard: "OrderedSet{'a', 'b', 'c'}"),
        .init("Set{'a', 'b'}->collect(s | 'x')", legacy: "Sequence{'x', 'x'}", standard: "Set{'x'}"),
        .init(
            "OrderedSet{'a', 'b'}->collect(s | Sequence{s, 'a'})",
            legacy: "Sequence{'a', 'a', 'b', 'a'}", standard: "OrderedSet{'a', 'b'}"),
        .init("OrderedSet{'a', 'b'}->union(Sequence{'c', 'c'})", legacy: "Sequence{'a', 'b', 'c'}", standard: "OrderedSet{'a', 'b', 'c'}"),
        .init("OrderedSet{1, 1, 2}", legacy: "Sequence{1, 2}", standard: "OrderedSet{1, 2}"),
        .init("Set{1, 1, 2}", legacy: "Sequence{1, 2}", standard: "Set{1, 2}"),
        .init("Bag{1, 1, 2}", legacy: "Sequence{1, 1, 2}", standard: "Bag{1, 1, 2}"),
        .init("Sequence{1, 1, 2}->asSet()", legacy: "Sequence{1, 2}", standard: "Set{1, 2}"),
        .init("Sequence{1, 1, 2}->asOrderedSet()", legacy: "Sequence{1, 2}", standard: "OrderedSet{1, 2}"),
        .init("OrderedSet{1, 2}->asBag()->including(1)", legacy: "Sequence{1, 2, 1}", standard: "Bag{1, 2, 1}"),
        .init(
            "OrderedSet{3}->closure(i | if i > 1 then i - 1 else null endif)",
            legacy: "Sequence{2, 1}", standard: "OrderedSet{2, 1}"),
        .init(
            "Sequence{3, 3}->closure(i | if i > 1 then i - 1 else null endif)->including(1)",
            legacy: "Sequence{2, 1, 1}", standard: "OrderedSet{2, 1}"),
        .init(
            "Set{3}->closure(i | if i > 1 then i - 1 else null endif)",
            legacy: "Sequence{2, 1}", standard: "Set{2, 1}"),
        .init("OrderedSet{'a', 'b'}->sep('-')", both: "Sequence{'a', '-', 'b'}"),
        .init("OrderedSet{'a', 'b'}->sep('[', '-', ']')", both: "Sequence{'[', 'a', '-', 'b', ']'}"),
        .init(
            "OrderedSet{Sequence{'a', 'a'}, Sequence{'b', 'a'}}->flatten()",
            legacy: "Sequence{'a', 'a', 'b', 'a'}", standard: "OrderedSet{'a', 'b'}"),
        .init("OrderedSet{'a', 'b'}->reverse()->append('a')", legacy: "Sequence{'b', 'a', 'a'}", standard: "OrderedSet{'b', 'a'}"),
        .init(
            "OrderedSet{'a', 'b'}->select(x | true)->including('a')",
            legacy: "Sequence{'a', 'b', 'a'}", standard: "OrderedSet{'a', 'b'}"),
        .init("Set{'a', 'b'}->asSequence()->append('a')", both: "Sequence{'a', 'b', 'a'}"),
        .init("OrderedSet{x, y}.name", legacy: "Sequence{'n', 'n'}", standard: "OrderedSet{'n'}"),
        .init("Set{x, y}.name->size()", legacy: "2", standard: "1"),
        .init("Sequence{x, y}.name", both: "Sequence{'n', 'n'}"),
    ]

    /// Arrow calls on values that are not collections.
    nonisolated static let singleValueExamples: [CompatibilityExample] = [
        .init("'a'->including('a')", legacy: "Sequence{'a', 'a'}", standard: "Set{'a'}"),
        .init("'a'->append('b')", legacy: "Sequence{'a', 'b'}", standard: "Set{'a', 'b'}"),
        .init("'a'->prepend('a')", legacy: "Sequence{'a', 'a'}", standard: "Set{'a'}"),
        .init("'a'->append('a')->size()", legacy: "2", standard: "1"),
        .init("null->including('a')", legacy: "Sequence{'a'}", standard: "Set{'a'}"),
        .init("null->asSequence()", both: "Sequence{}"),
        .init("'a'->size()", both: "1"),
        .init("null->size()", both: "0"),
        .init("x->including(x)->size()", legacy: "2", standard: "1"),
    ]

    /// All examples evaluated under both presets.
    nonisolated static let allExamples = collectionArgumentExamples + collectionKindExamples + singleValueExamples

    @Test("The legacy options compute the values of version 0.6.1, all as sequences", arguments: allExamples)
    func legacyValues(_ example: CompatibilityExample) async throws {
        let wanted = try await OptionsFixture.value(of: example.legacy, in: OptionsFixture.context(.standard))
        try await OptionsFixture.check(
            example.source, yields: example.legacy, with: .legacy,
            kinds: OptionsFixture.kinds(wanted).map { _ in .sequence })
    }

    @Test("The standard options keep collection kinds", arguments: allExamples)
    func standardValues(_ example: CompatibilityExample) async throws {
        try await OptionsFixture.check(example.source, yields: example.standard, with: .standard)
    }

    // MARK: Single options

    @Test("Only the first element of a collection argument is added", arguments: collectionArgumentExamples)
    func firstElementOnly(_ example: CompatibilityExample) async throws {
        let options = AQLOptions(collectionArguments: .firstElement, collectionKinds: .sequences)
        let wanted = try await OptionsFixture.value(of: example.legacy, in: OptionsFixture.context(.standard))
        try await OptionsFixture.check(
            example.source, yields: example.legacy, with: options,
            kinds: OptionsFixture.kinds(wanted).map { _ in .sequence })
    }

    /// Examples for one option changed from the standard options.
    nonisolated static let singleOptionExamples: [(AQLOptions, String, String)] = [
        (AQLOptions(collectionArguments: .firstElement), "Sequence{'a'}->append(Sequence{'b', 'c'})", "Sequence{'a', 'b'}"),
        (AQLOptions(collectionArguments: .firstElement), "OrderedSet{'a', 'b'}->append(OrderedSet{'b', 'c'})", "OrderedSet{'a', 'b'}"),
        (AQLOptions(collectionArguments: .firstElement), "OrderedSet{'a', 'b'}->prepend(Sequence{'b', 'c'})", "OrderedSet{'b', 'a'}"),
        (AQLOptions(collectionArguments: .firstElement), "'a'->including(Sequence{'a', 'c'})", "Set{'a'}"),
        (AQLOptions(collectionKinds: .sequences), "OrderedSet{'a', 'b'}->append(Sequence{'b', 'c'})", "Sequence{'a', 'b', Sequence{'b', 'c'}}"),
        (AQLOptions(collectionKinds: .sequences), "OrderedSet{'a', 'b'}->append('a')", "Sequence{'a', 'b', 'a'}"),
        (AQLOptions(collectionKinds: .sequences), "'a'->including('a')", "Sequence{'a', 'a'}"),
        (AQLOptions(singleValueCollections: .sequence), "'a'->including('a')", "Sequence{'a', 'a'}"),
        (AQLOptions(singleValueCollections: .sequence), "null->including('a')", "Sequence{'a'}"),
        (AQLOptions(singleValueCollections: .sequence), "OrderedSet{'a'}->including('a')", "OrderedSet{'a'}"),
        (AQLOptions(containerLookup: .registeredObjects), "OrderedSet{'a', 'b'}->append('a')", "OrderedSet{'b', 'a'}"),
    ]

    @Test("Each option changes only its own behaviour", arguments: singleOptionExamples.indices)
    func singleOption(_ index: Int) async throws {
        let (options, source, expected) = Self.singleOptionExamples[index]
        let kinds: [EcoreCollectionKind]? =
            options.collectionKinds == .sequences
            ? OptionsFixture.kinds(try await OptionsFixture.value(of: expected, in: OptionsFixture.context(.standard)))
                .map { _ in .sequence }
            : nil
        try await OptionsFixture.check(source, yields: expected, with: options, kinds: kinds)
    }

    @Test("Under the legacy options every collection counts as a sequence for services")
    func legacyReceiverKind() async throws {
        let context = makeContext(options: .legacy)
        context.register(KindReporter())
        let reported = try await OptionsFixture.value(of: "OrderedSet{1}.reportKind()", in: context)
        #expect(reported as? String == EcoreCollectionKind.sequence.rawValue)
        context.options = .standard
        let standard = try await OptionsFixture.value(of: "OrderedSet{1}.reportKind()", in: context)
        #expect(standard as? String == EcoreCollectionKind.orderedSet.rawValue)
    }

    @Test("Under the legacy options an arrow call sees a collection of any kind as a sequence")
    func legacyArrowReceiver() async throws {
        for kind in EcoreCollectionKind.allCases {
            let receiver = EcoreValueArray(["a"], kind: kind)
            let result = try await AQLCallExpression(
                source: lit(receiver), methodName: "including", arguments: [lit("a")], usesArrow: true
            ).evaluate(in: makeContext(options: .legacy))
            #expect(OptionsFixture.kinds(result) == [.sequence])
            #expect(AQLValues.areEqual(result, seq("a", "a")))
        }
    }

    @Test("Navigation over a collection value of a set kind", arguments: [AQLOptions.legacy, .standard])
    func navigationOverKindedValue(_ options: AQLOptions) async throws {
        let context = OptionsFixture.context(options)
        var objects: [any EcoreValue] = []
        for variable in OptionsFixture.objectVariables {
            objects.append(try #require(try await context.getVariable(variable)))
        }
        let result = try await context.navigate(from: EcoreValueArray(objects, kind: .orderedSet), property: "name")
        if options == .legacy {
            #expect(AQLValues.areEqual(result, seq("n", "n")))
            #expect(OptionsFixture.kinds(result) == [.sequence])
        } else {
            #expect(AQLValues.areEqual(result, seq("n")))
            #expect(OptionsFixture.kinds(result) == [.orderedSet])
        }
    }
}

/// A service reporting the collection kind that a call sees for its receiver.
private struct KindReporter: AQLServiceProvider {
    var services: [AQLService] {
        [AQLService("reportKind", receiver: .collection) { call in call.receiverKind.rawValue }]
    }
}
