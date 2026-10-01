//
//  AQLObjectServicesTests.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import AQL

/// A small containment tree: root > (a > (a1, a2), b), with b.peer = a.
@MainActor
struct TreeFixture {
    let nodeClass: EClass
    let leafClass: EClass
    let root: DynamicEObject
    let a: DynamicEObject
    let a1: DynamicEObject
    let a2: DynamicEObject
    let b: DynamicEObject
    let context: AQLExecutionContext

    init() async {
        let string = EDataType(name: "EString")
        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        node.eStructuralFeatures.append(
            EReference(name: "children", eType: node, upperBound: -1, containment: true))
        node.eStructuralFeatures.append(EReference(name: "peer", eType: node))
        var leaf = EClass(name: "Leaf")
        leaf.eSuperTypes = [node]
        nodeClass = node
        leafClass = leaf

        func make(_ name: String, _ eClass: EClass) -> DynamicEObject {
            var object = DynamicEObject(eClass: eClass)
            object.eSet("name", value: name)
            return object
        }
        var root = make("root", node)
        var a = make("a", node)
        let a1 = make("a1", leaf)
        let a2 = make("a2", leaf)
        var b = make("b", node)
        a.eSet("children", value: [a1.id, a2.id])
        root.eSet("children", value: [a.id, b.id])
        b.eSet("peer", value: a.id)

        let resource = Resource()
        for object in [root, a, a1, a2, b] { await resource.add(object) }
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "m")
        let context = AQLExecutionContext(executionEngine: engine)
        context.addResource(resource)
        self.root = root
        self.a = a
        self.a1 = a1
        self.a2 = a2
        self.b = b
        self.context = context
    }

    func names(_ value: (any EcoreValue)?) -> [String] {
        AQLValues.coerceToCollection(value).compactMap { ($0 as? DynamicEObject)?.eGet("name") as? String }
    }

    func call(_ receiver: any EcoreValue, _ method: String, _ arguments: any AQLExpression...) async throws
        -> (any EcoreValue)?
    {
        try await AQLCallExpression(source: lit(receiver), methodName: method, arguments: arguments)
            .evaluate(in: context)
    }
}

@MainActor
@Suite("AQL EObject services")
struct AQLObjectServicesTests {
    @Test("Contents and containers")
    func containment() async throws {
        let t = await TreeFixture()
        #expect(t.names(try await t.call(t.root, "eContents")) == ["a", "b"])
        #expect(t.names(try await t.call(t.a, "eContents")) == ["a1", "a2"])
        #expect(t.names(try await t.call(t.root, "eAllContents")) == ["a", "a1", "a2", "b"])
        #expect(t.names(try await t.call(t.root, "eAllContents", AQLTypeLiteralExpression(packageName: nil, typeName: "Leaf"))) == ["a1", "a2"])
        #expect(t.names(try await t.call(t.root, "eContents", AQLVariableExpression(name: "Leaf"))) == [])
        #expect((try await t.call(t.a1, "eContainer") as? DynamicEObject)?.id == t.a.id)
        #expect(try await t.call(t.root, "eContainer") == nil)
        #expect((try await t.call(t.a1, "eContainer", AQLVariableExpression(name: "Node")) as? DynamicEObject)?.id == t.a.id)
        #expect(t.names(try await t.call(t.a1, "ancestors")) == ["a", "root"])
        #expect(t.names(try await t.call(t.a1, "ancestors", AQLVariableExpression(name: "Leaf"))) == [])
    }

    @Test("Siblings")
    func siblings() async throws {
        let t = await TreeFixture()
        #expect(t.names(try await t.call(t.a1, "siblings")) == ["a2"])
        #expect(t.names(try await t.call(t.a2, "precedingSiblings")) == ["a1"])
        #expect(t.names(try await t.call(t.a1, "followingSiblings")) == ["a2"])
        #expect(t.names(try await t.call(t.root, "siblings")) == [])
    }

    @Test("Reflection: eClass, eGet, eInverse, allInstances")
    func reflection() async throws {
        let t = await TreeFixture()
        #expect((try await t.call(t.a1, "eClass") as? EClass)?.name == "Leaf")
        #expect(try await t.call(t.a, "eGet", lit("name")) as? String == "a")
        #expect(t.names(try await t.call(t.b, "eGet", lit("peer"))) == ["a"])
        #expect(Set(t.names(try await t.call(t.a, "eInverse"))) == ["root", "b"])
        let leaves = try await t.call(AQLTypeDescriptor(typeName: "Leaf"), "allInstances")
        #expect(Set(t.names(leaves)) == ["a1", "a2"])
        let nodes = try await t.call(AQLTypeDescriptor(typeName: "Node"), "allInstances")
        #expect(AQLValues.elements(of: nodes)?.count == 5)
    }

    @Test("Containment index caching")
    func caching() async throws {
        let t = await TreeFixture()
        t.context.cachesContainmentIndex = true
        #expect(t.names(try await t.call(t.a1, "ancestors")) == ["a", "root"])
        #expect(t.names(try await t.call(t.a1, "ancestors")) == ["a", "root"])
        t.context.invalidateContainmentIndex()
        #expect(t.names(try await t.call(t.a1, "ancestors")) == ["a", "root"])
    }

    @Test("Navigation across a collection collects")
    func implicitCollect() async throws {
        let t = await TreeFixture()
        t.context.setVariable("self", value: t.root)
        let children = try await AQLNavigationExpression(source: lit(t.root), property: "children").evaluate(in: t.context)
        let names = try await AQLNavigationExpression(source: lit(children), property: "name").evaluate(in: t.context)
        #expect(AQLValues.areEqual(names, seq("a", "b")))
    }

    // MARK: Type tests

    struct TypeCase: Sendable, CustomTestStringConvertible {
        let operation: String
        let typeName: String
        let expected: Bool
        var testDescription: String { "\(operation)(\(typeName)) = \(expected)" }
    }

    nonisolated static let typeCases: [TypeCase] = [
        TypeCase(operation: "oclIsKindOf", typeName: "Leaf", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "Node", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "t::Node", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "EObject", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "OclAny", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "Other", expected: false),
        TypeCase(operation: "oclIsTypeOf", typeName: "Leaf", expected: true),
        TypeCase(operation: "oclIsTypeOf", typeName: "Node", expected: false),
    ]

    @Test("Type operations on dynamic objects", arguments: typeCases)
    func typeOperations(_ test: TypeCase) async throws {
        let t = await TreeFixture()
        let result = try await AQLCallExpression(
            source: lit(t.a1), methodName: test.operation,
            arguments: [AQLTypeLiteralExpression(
                packageName: test.typeName.contains("::") ? "t" : nil,
                typeName: test.typeName.components(separatedBy: "::").last!)]
        ).evaluate(in: t.context)
        #expect(result as? Bool == test.expected)
        let viaName = try await AQLCallExpression(
            source: lit(t.a1), methodName: test.operation,
            arguments: [AQLVariableExpression(name: test.typeName)]
        ).evaluate(in: t.context)
        #expect(viaName as? Bool == test.expected)
    }

    nonisolated static let nativeCases: [TypeCase] = [
        TypeCase(operation: "oclIsKindOf", typeName: "ecore::EClass", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "ecore::EClassifier", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "ecore::ENamedElement", expected: true),
        TypeCase(operation: "oclIsKindOf", typeName: "ecore::EPackage", expected: false),
        TypeCase(operation: "oclIsTypeOf", typeName: "ecore::EClass", expected: true),
        TypeCase(operation: "oclIsTypeOf", typeName: "ecore::EClassifier", expected: false),
    ]

    @Test("Type operations on native Ecore objects", arguments: nativeCases)
    func nativeTypeOperations(_ test: TypeCase) async throws {
        let result = try await AQLCallExpression(
            source: lit(EClass(name: "Thing")), methodName: test.operation,
            arguments: [AQLVariableExpression(name: test.typeName)]
        ).evaluate(in: makeContext())
        #expect(result as? Bool == test.expected)
    }

    @Test("Native objects of other metaclasses")
    func nativeOthers() async throws {
        let context = makeContext()
        let package = EPackage(name: "p", nsURI: "u", nsPrefix: "p")
        let attribute = EAttribute(name: "x", eType: EDataType(name: "EString"))
        for (value, type, expected) in [
            (package as any EcoreValue, "ENamedElement", true),
            (attribute as any EcoreValue, "EStructuralFeature", true),
            (attribute as any EcoreValue, "EReference", false),
        ] {
            let result = try await AQLCallExpression(
                source: lit(value), methodName: "oclIsKindOf", arguments: [AQLVariableExpression(name: type)]
            ).evaluate(in: context)
            #expect(result as? Bool == expected)
        }
    }

    @Test("oclAsType returns the receiver and eClass works for native objects")
    func asTypeAndNativeClass() async throws {
        let context = makeContext()
        let eClass = EClass(name: "Thing")
        let cast = try await AQLCallExpression(
            source: lit(eClass), methodName: "oclAsType", arguments: [AQLVariableExpression(name: "EClass")]
        ).evaluate(in: context)
        #expect((cast as? EClass)?.name == "Thing")
        let metaClass = try await AQLCallExpression(source: lit(eClass), methodName: "eClass").evaluate(in: context)
        #expect(AQLTypeDescriptor(value: metaClass) != nil || metaClass is any EObject)
    }

    @Test("Primitive type tests")
    func primitives() async throws {
        let context = makeContext()
        for (value, type, expected) in [
            ("a" as any EcoreValue, "String", true), (1 as any EcoreValue, "Integer", true),
            (1 as any EcoreValue, "Real", false), (1.5 as any EcoreValue, "Real", true),
            (true as any EcoreValue, "Boolean", true), (seq(1) as any EcoreValue, "Sequence", true),
            ("a" as any EcoreValue, "Integer", false),
        ] {
            let result = try await AQLCallExpression(
                source: lit(value), methodName: "oclIsKindOf", arguments: [AQLVariableExpression(name: type)]
            ).evaluate(in: context)
            #expect(result as? Bool == expected)
        }
    }

    @Test("A bound variable holding a type is used as the type")
    func variableHoldingType() async throws {
        let context = makeContext()
        context.setVariable("T", value: AQLTypeDescriptor(typeName: "String"))
        let result = try await AQLCallExpression(
            source: lit("a"), methodName: "oclIsKindOf", arguments: [AQLVariableExpression(name: "T")]
        ).evaluate(in: context)
        #expect(result as? Bool == true)
    }
}
