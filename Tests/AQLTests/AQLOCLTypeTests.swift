//
//  AQLOCLTypeTests.swift
//  AQL
//
//  Created by Rene Hexel on 14/02/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import AQL

/// Tests for OCL type operations (oclIsKindOf, oclIsTypeOf, oclAsType).
@MainActor
struct AQLOCLTypeTests {

    // MARK: - Test Metamodel Setup

    /// Creates a simple class hierarchy: Shape (abstract) > Circle, Rectangle.
    func createTestMetamodel() -> (pkg: EPackage, shapeClass: EClass, circleClass: EClass, rectangleClass: EClass) {
        var pkg = EPackage(name: "shapes", nsURI: "http://example.com/shapes", nsPrefix: "shapes")

        // Data types
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")

        // Shape (abstract base class)
        var shapeClass = EClass(name: "Shape", isAbstract: true)
        let nameAttr = EAttribute(name: "name", eType: stringType)
        shapeClass.eStructuralFeatures.append(nameAttr)

        // Circle
        var circleClass = EClass(name: "Circle")
        circleClass.eSuperTypes.append(shapeClass)
        let radiusAttr = EAttribute(name: "radius", eType: intType)
        circleClass.eStructuralFeatures.append(radiusAttr)

        // Rectangle
        var rectangleClass = EClass(name: "Rectangle")
        rectangleClass.eSuperTypes.append(shapeClass)
        let widthAttr = EAttribute(name: "width", eType: intType)
        let heightAttr = EAttribute(name: "height", eType: intType)
        rectangleClass.eStructuralFeatures.append(widthAttr)
        rectangleClass.eStructuralFeatures.append(heightAttr)

        pkg.eClassifiers.append(shapeClass)
        pkg.eClassifiers.append(circleClass)
        pkg.eClassifiers.append(rectangleClass)

        return (pkg, shapeClass, circleClass, rectangleClass)
    }

    // MARK: - oclIsKindOf Tests

    @Test func testOclIsKindOfExactType() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        var circle = DynamicEObject(eClass: circleClass)
        circle.eSet("name", value: "MyCircle")
        circle.eSet("radius", value: 5)

        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclIsKindOf(Circle) → true
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsKindOf",
            arguments: [AQLVariableExpression(name: "Circle")]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == true)
    }

    @Test func testOclIsKindOfSuperType() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        var circle = DynamicEObject(eClass: circleClass)
        circle.eSet("name", value: "MyCircle")
        circle.eSet("radius", value: 5)

        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclIsKindOf(Shape) → true
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsKindOf",
            arguments: [AQLVariableExpression(name: "Shape")]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == true)
    }

    @Test func testOclIsKindOfUnrelatedType() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        var circle = DynamicEObject(eClass: circleClass)
        circle.eSet("name", value: "MyCircle")
        circle.eSet("radius", value: 5)

        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclIsKindOf(Rectangle) → false
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsKindOf",
            arguments: [AQLVariableExpression(name: "Rectangle")]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == false)
    }

    // MARK: - oclIsTypeOf Tests

    @Test func testOclIsTypeOfExactType() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        var circle = DynamicEObject(eClass: circleClass)
        circle.eSet("name", value: "MyCircle")
        circle.eSet("radius", value: 5)

        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclIsTypeOf(Circle) → true
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsTypeOf",
            arguments: [AQLVariableExpression(name: "Circle")]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == true)
    }

    @Test func testOclIsTypeOfSuperType() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        var circle = DynamicEObject(eClass: circleClass)
        circle.eSet("name", value: "MyCircle")
        circle.eSet("radius", value: 5)

        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclIsTypeOf(Shape) → false (not exact type)
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsTypeOf",
            arguments: [AQLVariableExpression(name: "Shape")]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == false)
    }

    // MARK: - oclAsType Tests

    @Test func testOclAsTypeReturnsObject() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        let circle = DynamicEObject(eClass: circleClass)

        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclAsType(Circle) → same object (for dynamic models, no-op)
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclAsType",
            arguments: [AQLVariableExpression(name: "Circle")]
        )

        let result = try await expr.evaluate(in: context)
        // For structs, we check the eClass.name instead
        let resultObj = result as? DynamicEObject
        #expect(resultObj?.eClass.name == "Circle")
    }

    // MARK: - Error Cases

    @Test func testOclIsKindOfMissingArgument() async throws {
        let (_, _, circleClass, _) = createTestMetamodel()

        let circle = DynamicEObject(eClass: circleClass)
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: circle)

        // c.oclIsKindOf() → error
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsKindOf",
            arguments: []
        )

        await #expect(throws: AQLExecutionError.self) {
            try await expr.evaluate(in: context)
        }
    }

    @Test func testOclIsKindOfNullSource() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)
        context.setVariable("c", value: nil)

        // null.oclIsKindOf(Circle) → false
        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "c"),
            methodName: "oclIsKindOf",
            arguments: [AQLVariableExpression(name: "Circle")]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == false)
    }
}
