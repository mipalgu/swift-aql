//
//  AQLCollectionKindTests.swift
//  AQL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// An AQL expression and the AQL expression denoting its expected value.
struct KindExample: Sendable, CustomTestStringConvertible {
    /// The expression under test.
    let source: String
    /// The expression whose value, including its collection kind, is expected.
    let expected: String

    init(_ source: String, _ expected: String) {
        self.source = source
        self.expected = expected
    }

    /// The same example with every occurrence of one text replaced by another.
    func replacing(_ text: String, with replacement: String) -> KindExample {
        KindExample(
            source.replacingOccurrences(of: text, with: replacement),
            expected.replacingOccurrences(of: text, with: replacement))
    }

    var testDescription: String { "\(source) = \(expected)" }
}

@MainActor
@Suite("AQL Collection kinds")
struct AQLCollectionKindTests {

    // MARK: Support

    /// Parses and evaluates AQL text in the given context.
    static func value(of source: String, in context: AQLExecutionContext = makeContext()) async throws
        -> (any EcoreValue)?
    {
        let parsed = AQLParser().parse(source)
        let expression = try #require(parsed.expression, "\(parsed.diagnostics)")
        return try await expression.evaluate(in: context)
    }

    /// The collection kind of a value, or nil if it is not an `EcoreValueArray`.
    static func kind(_ value: (any EcoreValue)?) -> EcoreCollectionKind? {
        (value as? EcoreValueArray)?.kind
    }

    /// Checks that an example yields the elements and the kind of its expected value.
    static func check(_ example: KindExample) async throws {
        let result = try await value(of: example.source)
        let expected = try await value(of: example.expected)
        #expect(AQLValues.areEqual(result, expected), "got \(AQLValues.description(of: result))")
        #expect(kind(result) == kind(expected))
    }

    // MARK: Acceleo examples

    /// The Acceleo examples of the set variants of the collection services.
    nonisolated static let orderedSetExamples: [KindExample] = [
        KindExample("OrderedSet{'a', 'b', 'c'}.concat(Sequence{'d', 'e'})", "OrderedSet{'a', 'b', 'c', 'd', 'e'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.addAll(Sequence{'d', 'e'})", "OrderedSet{'a', 'b', 'c', 'd', 'e'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.addAll(OrderedSet{'c', 'b', 'f'})", "OrderedSet{'a', 'b', 'c', 'f'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.removeAll(OrderedSet{'c', 'b', 'f'})", "OrderedSet{'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->select(str | str.equals('a'))", "OrderedSet{'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->reject(str | str.equals('a'))", "OrderedSet{'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->collect(str | str.toUpper())", "OrderedSet{'A', 'B', 'C'}"),
        KindExample("OrderedSet{'aa', 'bbb', 'c'}->sortedBy(str | str.size())", "OrderedSet{'c', 'aa', 'bbb'}"),
        KindExample("OrderedSet{'a', 'b', 'c', 'd'}->size()", "4"),
        KindExample("OrderedSet{'a', 'b', 'c'}->including('d')", "OrderedSet{'a', 'b', 'c', 'd'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->excluding('c')", "OrderedSet{'a', 'b'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->asSequence()", "Sequence{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->reverse()", "OrderedSet{'c', 'b', 'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->isEmpty()", "false"),
        KindExample("OrderedSet{'a', 'b', 'c'}->notEmpty()", "true"),
        KindExample("OrderedSet{'a', 'b', 'c'}->at(1)", "'a'"),
        KindExample("OrderedSet{'a', 'b', 'c'}->at(2)", "'b'"),
        KindExample("OrderedSet{'a', 1, 3.14}->filter(String)", "OrderedSet{'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->sep('-')", "Sequence{'a', '-', 'b', '-', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->last()", "'c'"),
        KindExample("OrderedSet{'a', 'b', 'c'}->union(OrderedSet{'d', 'c'})", "OrderedSet{'a', 'b', 'c', 'd'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->count('d')", "0"),
        KindExample("OrderedSet{'a', 'b', 'c'}->count('a')", "1"),
        KindExample("OrderedSet{1, 2, 3, 4}->indexOf(3)", "3"),
        KindExample("OrderedSet{1, 2, 3, 4}->lastIndexOf(3)", "3"),
        KindExample("OrderedSet{'a', 'b', 'c'}->insertAt(2, 'f')", "OrderedSet{'a', 'f', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->append('f')", "OrderedSet{'a', 'b', 'c', 'f'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->append('b')", "OrderedSet{'a', 'c', 'b'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->prepend('f')", "OrderedSet{'f', 'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->intersection(OrderedSet{'a', 'f'})", "OrderedSet{'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->subOrderedSet(1, 2)", "OrderedSet{'a', 'b'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->drop(2)", "OrderedSet{'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->dropRight(2)", "OrderedSet{'a'}"),
        // Acceleo writes every set as an OrderedSet; asSet yields a Set.
        KindExample("OrderedSet{'a', 'b', 'c'}->asSet()", "Set{'a', 'b', 'c'}"),
        KindExample("Sequence{'a', 'b', 'c', 'c', 'a'}->asSet()", "Set{'a', 'b', 'c'}"),
    ]

    /// The Acceleo examples of the set variants whose result depends on the conversion target.
    nonisolated static let conversionExamples: [KindExample] = [
        KindExample("OrderedSet{'a', 'b', 'c'}->asOrderedSet()", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("Sequence{'a', 'b', 'c'}->asOrderedSet()", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("Set{'a', 'b', 'c'}->asOrderedSet()", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("Set{'a', 'b', 'c'}->asSequence()", "Sequence{'a', 'b', 'c'}"),
        KindExample("Sequence{'a', 'a'}->asBag()", "Bag{'a', 'a'}"),
        KindExample("OrderedSet{'a', 'b'}->asBag()", "Bag{'a', 'b'}"),
        KindExample("Bag{'a', 'a'}->asSequence()", "Sequence{'a', 'a'}"),
        KindExample("Bag{'a', 'a'}->asOrderedSet()", "OrderedSet{'a'}"),
    ]

    /// The Acceleo examples of the sequence variants that take a set argument.
    nonisolated static let mixedExamples: [KindExample] = [
        KindExample("Sequence{'a', 'b', 'c'}.addAll(OrderedSet{'c', 'e'})", "Sequence{'a', 'b', 'c', 'c', 'e'}"),
        KindExample("Sequence{'a', 'b', 'c'}.removeAll(OrderedSet{'c', 'b', 'f'})", "Sequence{'a'}"),
        KindExample("Sequence{'a', 'b', 'c'}->intersection(OrderedSet{'a', 'f'})", "Sequence{'a'}"),
    ]

    @Test("Acceleo examples for ordered sets", arguments: orderedSetExamples)
    func orderedSetExample(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Acceleo examples for sets", arguments: orderedSetExamples.map { $0.replacing("OrderedSet{", with: "Set{") })
    func setExample(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Conversions yield the requested kind", arguments: conversionExamples)
    func conversion(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Sequences keep their kind with set arguments", arguments: mixedExamples)
    func mixedExample(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Bags keep their kind with set arguments", arguments: mixedExamples.map { $0.replacing("Sequence{", with: "Bag{") })
    func bagExample(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    // MARK: Elements already present

    /// Adding an element that a unique collection already holds.
    nonisolated static let uniqueAdditions: [KindExample] = [
        KindExample("OrderedSet{'a', 'b', 'c'}->append('a')", "OrderedSet{'b', 'c', 'a'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->append('c')", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->prepend('b')", "OrderedSet{'b', 'a', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->prepend('a')", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}->including('a')", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b', 'c'}.including('b')", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{1, 2, 3}->insertAt(2, 4)", "OrderedSet{1, 4, 2, 3}"),
        KindExample("OrderedSet{1, 2, 3}->insertAt(1, 3)", "OrderedSet{3, 1, 2}"),
        KindExample("OrderedSet{1, 2, 3}->insertAt(4, 1)", "OrderedSet{2, 3, 1}"),
        KindExample("OrderedSet{1, 2, 3}->insertAt(2, 2)", "OrderedSet{1, 2, 3}"),
        KindExample("OrderedSet{1, 2, 3}->insertAt(5, 4)", "null"),
        KindExample("OrderedSet{1, OrderedSet{'s'}, 2}->insertAt(3, OrderedSet{'s'})", "OrderedSet{1, 2, OrderedSet{'s'}}"),
        KindExample("OrderedSet{Sequence{'a'}, 'b'}->append(Sequence{'a'})", "OrderedSet{'b', Sequence{'a'}}"),
        KindExample("OrderedSet{'a', 'b'}->including(Sequence{'a'})", "OrderedSet{'a', 'b', Sequence{'a'}}"),
        KindExample("OrderedSet{'a', 'b'}->append(null)", "OrderedSet{'a', 'b'}"),
        KindExample("OrderedSet{'a', 'b'}->concat(Sequence{'b', 'c', 'c'})", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b'}->union(Sequence{'c', 'c'})", "OrderedSet{'a', 'b', 'c'}"),
        KindExample("OrderedSet{'a', 'b'}->collect(str | 'x')", "OrderedSet{'x'}"),
        KindExample("OrderedSet{'a', 'b'}->collect(str | Sequence{str, 'a'})", "OrderedSet{'a', 'b'}"),
        KindExample("OrderedSet{Sequence{'a', 'a'}, Sequence{'b', 'a'}}->flatten()", "OrderedSet{'a', 'b'}"),
    ]

    /// Adding an element that a non-unique collection already holds.
    nonisolated static let repeatedAdditions: [KindExample] = [
        KindExample("Sequence{'a', 'b', 'c'}->append('a')", "Sequence{'a', 'b', 'c', 'a'}"),
        KindExample("Sequence{'a', 'b', 'c'}->prepend('b')", "Sequence{'b', 'a', 'b', 'c'}"),
        KindExample("Sequence{'a', 'b', 'c'}->including('a')", "Sequence{'a', 'b', 'c', 'a'}"),
        KindExample("Sequence{1, 2, 3}->insertAt(1, 3)", "Sequence{3, 1, 2, 3}"),
        KindExample("Sequence{'a', 'b'}->concat(Sequence{'b', 'c', 'c'})", "Sequence{'a', 'b', 'b', 'c', 'c'}"),
        KindExample("Sequence{'a', 'b'}->collect(str | 'x')", "Sequence{'x', 'x'}"),
        KindExample("Sequence{Sequence{'a', 'a'}, Sequence{'b', 'a'}}->flatten()", "Sequence{'a', 'a', 'b', 'a'}"),
    ]

    @Test("Ordered sets move or keep an element already present", arguments: uniqueAdditions)
    func orderedSetAddition(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Sets move or keep an element already present", arguments: uniqueAdditions.map { $0.replacing("OrderedSet{", with: "Set{") })
    func setAddition(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Sequences add an element already present again", arguments: repeatedAdditions)
    func sequenceAddition(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("Bags add an element already present again", arguments: repeatedAdditions.map { $0.replacing("Sequence{", with: "Bag{") })
    func bagAddition(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    // MARK: Result kinds

    /// Operations whose result has the kind of the receiver.
    nonisolated static let kindPreservingOperations = [
        "->select(x | true)", "->reject(x | false)", "->collect(x | x)", "->sortedBy(x | x)", "->reverse()",
        "->including('a')", "->excluding('a')", "->append('a')", "->prepend('a')", "->insertAt(1, 'a')",
        "->union(Sequence{'d'})", "->intersection(Sequence{'a'})", "->sub(Sequence{'a'})",
        "->concat(Sequence{'d'})", "->addAll(Sequence{'d'})", "->drop(1)", "->dropRight(1)",
        "->subSequence(1, 2)", "->subOrderedSet(1, 2)", "->filter(String)", "->flatten()",
    ]

    @Test(
        "Transformations keep the kind of the receiver",
        arguments: EcoreCollectionKind.allCases, kindPreservingOperations)
    func kindPreserved(_ kind: EcoreCollectionKind, _ operation: String) async throws {
        let result = try await Self.value(of: "\(kind.rawValue){'a', 'b', 'c'}\(operation)")
        #expect(Self.kind(result) == kind)
    }

    @Test("Separating yields a sequence", arguments: EcoreCollectionKind.allCases)
    func separatorKind(_ kind: EcoreCollectionKind) async throws {
        for operation in ["->sep('-')", "->sep('[', '-', ']')", "->sep('[', '-', ']', true)"] {
            let result = try await Self.value(of: "\(kind.rawValue){'a', 'b'}\(operation)")
            #expect(Self.kind(result) == .sequence)
        }
    }

    @Test("A closure is unique and as ordered as its receiver", arguments: EcoreCollectionKind.allCases)
    func closureKind(_ kind: EcoreCollectionKind) async throws {
        let result = try await Self.value(of: "\(kind.rawValue){3}->closure(i | if i > 1 then i - 1 else null endif)")
        #expect(AQLValues.areEqual(result, seq(2, 1)))
        #expect(Self.kind(result) == EcoreCollectionKind(ordered: kind.isOrdered, unique: true))
    }

    @Test("Collection literals have their kind", arguments: EcoreCollectionKind.allCases)
    func literalKind(_ kind: EcoreCollectionKind) async throws {
        let result = try await Self.value(of: "\(kind.rawValue){1, 1, 2}")
        #expect(Self.kind(result) == kind)
        #expect(AQLValues.elements(of: result)?.count == (kind.isUnique ? 2 : 3))
    }

    @Test("Collection literal kinds are the collection kinds")
    func literalKindType() {
        let kind: AQLCollectionLiteralExpression.Kind = .orderedSet
        #expect(kind == EcoreCollectionKind.orderedSet)
    }

    @Test("The textual form does not depend on the kind", arguments: EcoreCollectionKind.allCases)
    func textualForm(_ kind: EcoreCollectionKind) async throws {
        let result = try await Self.value(of: "\(kind.rawValue){'a', 'b'}.toString()")
        #expect(result as? String == "[a, b]")
    }

    // MARK: Implicit collections

    /// Arrow calls on values that are not collections.
    nonisolated static let implicitSets: [KindExample] = [
        KindExample("'a'->including('a')", "Set{'a'}"),
        KindExample("'a'->append('b')", "Set{'a', 'b'}"),
        KindExample("'a'->prepend('a')", "Set{'a'}"),
        KindExample("null->including('a')", "Set{'a'}"),
        KindExample("null->asSequence()", "Sequence{}"),
        KindExample("Sequence{'a'}->including('a')", "Sequence{'a', 'a'}"),
    ]

    @Test("An arrow call on a single value sees a set", arguments: implicitSets)
    func implicitSet(_ example: KindExample) async throws {
        try await Self.check(example)
    }

    @Test("An arrow call keeps the kind of a collection receiver", arguments: EcoreCollectionKind.allCases)
    func arrowKeepsKind(_ kind: EcoreCollectionKind) async throws {
        let receiver = EcoreValueArray(["a"], kind: kind)
        let result = try await AQLCallExpression(
            source: lit(receiver), methodName: "reverse", arguments: [], usesArrow: true
        ).evaluate(in: makeContext())
        #expect(Self.kind(result) == kind)
    }

    @Test("An arrow call sees a native array as a sequence")
    func nativeArray() async throws {
        let result = try await AQLCallExpression(
            source: lit(["a", "a"]), methodName: "including", arguments: [lit("a")], usesArrow: true
        ).evaluate(in: makeContext())
        #expect(Self.kind(result) == .sequence)
        #expect(AQLValues.elements(of: result)?.count == 3)
    }

    // MARK: Navigation

    /// Two objects whose `name` features are equal.
    static func namedObjects(in context: AQLExecutionContext) -> AQLExecutionContext {
        var eClass = EClass(name: "Named")
        eClass.eStructuralFeatures.append(EAttribute(name: "name", eType: EDataType(name: "EString")))
        for variable in ["x", "y"] {
            var object = DynamicEObject(eClass: eClass)
            object.eSet("name", value: "n")
            context.setVariable(variable, value: object)
        }
        return context
    }

    @Test("Navigating from a collection keeps its kind and uniqueness", arguments: EcoreCollectionKind.allCases)
    func navigation(_ kind: EcoreCollectionKind) async throws {
        let context = Self.namedObjects(in: makeContext())
        let result = try await Self.value(of: "\(kind.rawValue){x, y}.name", in: context)
        #expect(Self.kind(result) == kind)
        #expect(AQLValues.areEqual(result, kind.isUnique ? seq("n") : seq("n", "n")))
    }

    // MARK: Value helpers

    @Test("The kind of a value", arguments: EcoreCollectionKind.allCases)
    func kindOfValue(_ kind: EcoreCollectionKind) {
        #expect(AQLValues.kind(of: EcoreValueArray([], kind: kind)) == kind)
        #expect(AQLValues.collection([1], kind: kind).kind == kind)
    }

    @Test("Values that are not kinded collections")
    func kindOfOtherValues() {
        #expect(AQLValues.kind(of: ["a"]) == .sequence)
        #expect(AQLValues.kind(of: "a") == nil)
        #expect(AQLValues.kind(of: nil) == nil)
        #expect(AQLValues.collection([1]).kind == .sequence)
    }
}
