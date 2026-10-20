//
//  AQLUnsetFeatureTests.swift
//  AQL
//
//  Created by Rene Hexel on 21/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// A self-authored metamodel whose features are all left unset.
///
/// One class declares a Boolean, an integer, a double, an integer with a declared default,
/// an enumeration, a string, a many-valued attribute and a many-valued reference.
enum UnsetFixture {

    /// The features of the fixture class, named by their raw values.
    enum Feature: String, CaseIterable {
        /// A Boolean attribute.
        case flag
        /// An integer attribute.
        case count
        /// A double attribute.
        case weight
        /// An integer attribute with a declared default value literal.
        case limit
        /// An enumeration attribute.
        case colour
        /// A string attribute.
        case label
        /// A many-valued string attribute.
        case tags
        /// A many-valued reference.
        case links
    }

    /// The name of the variable bound to the object under test.
    static let variable = "x"

    /// The default that ``Feature/limit`` declares.
    static let limitDefault: EInt = 7

    /// The literals of the enumeration, in declaration order.
    static let colours = ["amber", "teal"]

    /// The upper bound denoting an unbounded multiplicity.
    static let unbounded = -1

    /// Creates an instance of the fixture class with no feature set.
    ///
    /// - Returns: The object.
    static func makeObject() -> DynamicEObject {
        func type(_ dataType: EcoreDataType) -> EDataType { EDataType(name: dataType.rawValue) }
        let colour = EEnum(
            name: "Colour",
            literals: colours.enumerated().map { EEnumLiteral(name: $1, value: $0) })
        var item = EClass(name: "Item")
        item.eStructuralFeatures = [
            EAttribute(name: Feature.flag.rawValue, eType: type(.eBoolean)),
            EAttribute(name: Feature.count.rawValue, eType: type(.eInt)),
            EAttribute(name: Feature.weight.rawValue, eType: type(.eDouble)),
            EAttribute(
                name: Feature.limit.rawValue, eType: type(.eInt),
                defaultValueLiteral: String(limitDefault)),
            EAttribute(name: Feature.colour.rawValue, eType: colour),
            EAttribute(name: Feature.label.rawValue, eType: type(.eString)),
            EAttribute(name: Feature.tags.rawValue, eType: type(.eString), upperBound: unbounded),
        ]
        let target = item
        item.eStructuralFeatures.append(
            EReference(name: Feature.links.rawValue, eType: target, upperBound: unbounded))
        return DynamicEObject(eClass: item)
    }

    /// Creates a context with a fresh fixture object bound to ``variable``.
    ///
    /// - Parameter context: The context to bind the object in.
    /// - Returns: The same context.
    @MainActor
    static func bind(_ context: AQLExecutionContext) -> AQLExecutionContext {
        context.setVariable(variable, value: makeObject())
        return context
    }

    /// The texts that read an unset feature, each of which yields nil in the undefined mode.
    static let undefinedReads: [String] =
        Feature.allCases.map { read($0) } + ["not \(read(.flag))", eGet(.flag)]

    /// The AQL text calling the `eGet` service for a feature of the bound object.
    ///
    /// - Parameter feature: The feature to read.
    /// - Returns: The service call expression.
    static func eGet(_ feature: Feature) -> String { "\(variable).eGet('\(feature.rawValue)')" }

    /// The AQL text navigating a feature of the bound object.
    ///
    /// - Parameter feature: The feature to navigate.
    /// - Returns: The navigation expression.
    static func read(_ feature: Feature) -> String { "\(variable).\(feature.rawValue)" }

    /// Parses and evaluates AQL text.
    ///
    /// - Parameters:
    ///   - source: The AQL text.
    ///   - context: The context to evaluate in.
    /// - Returns: The value of the expression.
    @MainActor
    static func evaluate(_ source: String, in context: AQLExecutionContext) async throws
        -> (any EcoreValue)?
    {
        let parsed = AQLParser().parse(source)
        let expression = try #require(parsed.expression, "\(parsed.diagnostics)")
        return try await expression.evaluate(in: context)
    }
}

/// How a test obtains a context that reads unset features as their defaults.
enum DefaultsContextFactory: String, CaseIterable, Sendable {
    /// A context around an engine created with default arguments.
    case plainEngine
    /// A context created by the convenience initialiser with default arguments.
    case convenience

    /// Creates the context.
    ///
    /// - Returns: A context with the fixture object bound.
    @MainActor
    func make() -> AQLExecutionContext {
        switch self {
        case .plainEngine:
            return AQLExecutionContext(executionEngine: ECoreExecutionEngine(models: [:]))
        case .convenience:
            return AQLExecutionContext()
        }
    }
}

@MainActor
@Suite("AQL reads of unset features")
struct AQLUnsetFeatureTests {
    typealias Fixture = UnsetFixture

    private func evaluate(_ source: String, _ factory: DefaultsContextFactory) async throws
        -> (any EcoreValue)?
    {
        try await Fixture.evaluate(source, in: Fixture.bind(factory.make()))
    }

    // MARK: - Defaults

    @Test("An unset Boolean reads as false and its negation as true", arguments: DefaultsContextFactory.allCases)
    func booleanDefault(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.read(.flag), factory) as? EBoolean == false)
        #expect(try await evaluate("not \(Fixture.read(.flag))", factory) as? EBoolean == true)
    }

    @Test("An unset integer reads as zero", arguments: DefaultsContextFactory.allCases)
    func integerDefault(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.read(.count), factory) as? EInt == 0)
    }

    @Test("An unset double reads as zero", arguments: DefaultsContextFactory.allCases)
    func doubleDefault(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.read(.weight), factory) as? EDouble == 0)
    }

    @Test("An unset attribute reads as its declared default", arguments: DefaultsContextFactory.allCases)
    func declaredDefault(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.read(.limit), factory) as? EInt == Fixture.limitDefault)
    }

    @Test("An unset enumeration reads as its first literal", arguments: DefaultsContextFactory.allCases)
    func enumerationDefault(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.read(.colour), factory) as? String == Fixture.colours.first)
    }

    @Test("An unset string stays undefined", arguments: DefaultsContextFactory.allCases)
    func stringUndefined(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.read(.label), factory) == nil)
        #expect(try await evaluate("\(Fixture.read(.label)).oclIsUndefined()", factory) as? EBoolean == true)
    }

    @Test(
        "Unset many-valued features read as empty collections",
        arguments: DefaultsContextFactory.allCases, [UnsetFixture.Feature.tags, .links])
    func manyValuedEmpty(factory: DefaultsContextFactory, feature: UnsetFixture.Feature)
        async throws
    {
        let read = Fixture.read(feature)
        let value = try await evaluate(read, factory)
        #expect(AQLValues.elements(of: value)?.isEmpty == true, "got \(AQLValues.description(of: value))")
        #expect(try await evaluate("\(read)->size()", factory) as? EInt == 0)
        #expect(try await evaluate("\(read)->isEmpty()", factory) as? EBoolean == true)
        #expect(try await evaluate("\(read).oclIsUndefined()", factory) as? EBoolean == false)
    }

    @Test("The eGet service reads an unset Boolean as false", arguments: DefaultsContextFactory.allCases)
    func eGetDefault(factory: DefaultsContextFactory) async throws {
        #expect(try await evaluate(Fixture.eGet(.flag), factory) as? EBoolean == false)
    }

    @Test("The convenience initialiser reads defaults unless told otherwise")
    func convenienceMode() async throws {
        #expect(await AQLExecutionContext().executionEngine.unsetFeatureReads == .defaults)
        let undefined = AQLExecutionContext(unsetFeatureReads: .undefined)
        #expect(await undefined.executionEngine.unsetFeatureReads == .undefined)
    }

    // MARK: - Undefined mode

    @Test("An undefined-mode engine reads unset features as nil", arguments: UnsetFixture.undefinedReads)
    func undefinedEngine(source: String) async throws {
        let engine = ECoreExecutionEngine(models: [:], unsetFeatureReads: .undefined)
        let context = Fixture.bind(AQLExecutionContext(executionEngine: engine))
        let value = try await Fixture.evaluate(source, in: context)
        #expect(value == nil, "got \(AQLValues.description(of: value))")
    }

    @Test("An undefined-mode convenience context reads unset features as nil", arguments: UnsetFixture.undefinedReads)
    func undefinedConvenience(source: String) async throws {
        let context = Fixture.bind(AQLExecutionContext(unsetFeatureReads: .undefined))
        let value = try await Fixture.evaluate(source, in: context)
        #expect(value == nil, "got \(AQLValues.description(of: value))")
    }

    @Test("Switching the engine to the undefined mode takes effect immediately", arguments: UnsetFixture.undefinedReads)
    func switchedEngine(source: String) async throws {
        let context = Fixture.bind(AQLExecutionContext())
        _ = try await Fixture.evaluate(source, in: context)
        await context.executionEngine.setUnsetFeatureReads(.undefined)
        let value = try await Fixture.evaluate(source, in: context)
        #expect(value == nil, "got \(AQLValues.description(of: value))")
    }
}
