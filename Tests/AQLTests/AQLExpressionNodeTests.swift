//
//  AQLExpressionNodeTests.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

@MainActor
@Suite("AQL expression nodes")
struct AQLExpressionNodeTests {
    @Test("Type literal evaluates to a descriptor")
    func typeLiteral() async throws {
        let value = try await AQLTypeLiteralExpression(packageName: "ecore", typeName: "EClass")
            .evaluate(in: makeContext())
        let descriptor = try #require(value as? AQLTypeDescriptor)
        #expect(descriptor.packageName == "ecore")
        #expect(descriptor.typeName == "EClass")
        #expect(descriptor.qualifiedName == "ecore::EClass")
        #expect(AQLTypeDescriptor(qualifiedName: "a::b::C").packageName == "a::b")
        #expect(AQLTypeDescriptor(qualifiedName: "C").packageName == nil)
        #expect(AQLTypeDescriptor(value: EClass(name: "K"))?.typeName == "K")
        #expect(AQLTypeDescriptor(value: EEnum(name: "E"))?.typeName == "E")
        #expect(AQLTypeDescriptor(value: 1) == nil)
    }

    @Test("Type literal drives filter")
    func typeLiteralFilter() async throws {
        let result = try await AQLCallExpression(
            source: lit(seq("a", 1)), methodName: "filter",
            arguments: [AQLTypeLiteralExpression(packageName: nil, typeName: "String")], usesArrow: true
        ).evaluate(in: makeContext())
        #expect(AQLValues.areEqual(result, seq("a")))
    }

    @Test("Enum literal evaluates to the literal name held by enum attributes")
    func enumLiteral() async throws {
        var eClass = EClass(name: "Holder")
        eClass.eStructuralFeatures.append(EAttribute(name: "kind", eType: EDataType(name: "Kind")))
        var holder = DynamicEObject(eClass: eClass)
        holder.eSet("kind", value: "Editable")
        let literal = AQLEnumLiteralExpression(packageName: "gen", enumName: "Kind", literal: "Editable")
        let value = try await literal.evaluate(in: makeContext())
        #expect(value as? String == "Editable")
        let comparison = try await AQLBinaryExpression(
            left: AQLNavigationExpression(source: lit(holder), property: "kind"), op: .equals, right: literal
        ).evaluate(in: makeContext())
        #expect(comparison as? Bool == true)
    }

    @Test("Collection literals keep objects", arguments: [
        AQLCollectionLiteralExpression.Kind.sequence, .orderedSet, .set, .bag,
    ])
    func collectionLiteral(_ kind: AQLCollectionLiteralExpression.Kind) async throws {
        let object = DynamicEObject(eClass: EClass(name: "Thing"))
        let value = try await AQLCollectionLiteralExpression(
            kind: kind, elements: [lit(object), lit(object), lit(1), lit(nil)]
        ).evaluate(in: makeContext())
        let items = try #require(AQLValues.elements(of: value))
        #expect((items.first as? DynamicEObject)?.id == object.id)
        let duplicatesRemoved = kind == .orderedSet || kind == .set
        #expect(items.count == (duplicatesRemoved ? 2 : 3))
    }

    @Test("Lambda expression yields a lambda that binds its iterator")
    func lambda() async throws {
        let context = makeContext()
        let value = try await AQLLambdaExpression(iterator: "x", body: AQLVariableExpression(name: "x")).evaluate(in: context)
        let lambda = try #require(value as? AQLLambda)
        #expect(try await lambda.invoke(7, in: context) as? Int == 7)
        #expect(lambda == lambda)
        #expect(lambda != AQLLambda(iterators: ["x"], body: lit(1)))
        #expect(lambda.hashValue == lambda.hashValue)
        await #expect(throws: AQLExecutionError.self) { _ = try await lambda.invoke(7, in: makeContext()).self; _ = try await AQLVariableExpression(name: "x").evaluate(in: makeContext()) }
    }

    @Test("Value helpers")
    func valueHelpers() {
        #expect(AQLValues.compare(1, 2) == .orderedAscending)
        #expect(AQLValues.compare(2.5, 2) == .orderedDescending)
        #expect(AQLValues.compare("a", "a") == .orderedSame)
        #expect(AQLValues.compare(false, true) == .orderedAscending)
        #expect(AQLValues.compare("a", 1) == nil)
        #expect(AQLValues.description(of: nil) == "null")
        #expect(AQLValues.description(of: AQLTypeDescriptor(qualifiedName: "a::B")) == "a::B")
        #expect(AQLValues.description(of: DynamicEObject(eClass: EClass(name: "K"))).hasPrefix("K@"))
        #expect(AQLValues.integer(Int8(3)) == 3)
        #expect(AQLValues.numericValue(Float(1.5)) == 1.5)
        #expect(!AQLValues.areEqual(seq(1), seq(1, 2)))
        #expect(!AQLValues.areEqual(DynamicEObject(eClass: EClass(name: "K")), "x"))
        #expect(AQLEcoreMetaTypes.allSuperTypes(of: "EEnum").contains("ENamedElement"))
    }
}
