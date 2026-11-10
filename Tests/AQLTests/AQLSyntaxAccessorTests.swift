//
//  AQLSyntaxAccessorTests.swift
//  AQLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import AQL
import Testing

/// Verifies that tools outside the module can read the parts of the syntax tree that
/// analyses of expressions need, such as the parts of string interpolations and the declared
/// types of iterators.
@Suite("Syntax tree accessors")
struct AQLSyntaxAccessorTests {
    @Test("The parts of a string interpolation are visible")
    func interpolationParts() throws {
        let expression = AQLStringInterpolationExpression(parts: [
            .init(literal: "Hello "),
            .init(literal: "", expression: AQLVariableExpression(name: "name")),
        ])
        #expect(expression.parts.map(\.literal) == ["Hello ", ""])
        #expect(expression.parts[0].expression == nil)
        let variable = try #require(expression.parts[1].expression as? AQLVariableExpression)
        #expect(variable.name == "name")
    }

    @Test("A lambda keeps the declared types of its iterators")
    func lambdaIteratorTypes() throws {
        let typed = try #require(AQLParser().parse("self.visit(e : ecore::EClass | e.name)").expression)
        let typedLambda = try #require((typed as? AQLCallExpression)?.arguments.first as? AQLLambdaExpression)
        #expect(typedLambda.iterators == ["e"])
        #expect(typedLambda.iteratorTypes == ["ecore::EClass"])
        let untyped = try #require(AQLParser().parse("self.visit(e | e.name)").expression)
        let untypedLambda = try #require((untyped as? AQLCallExpression)?.arguments.first as? AQLLambdaExpression)
        #expect(untypedLambda.iteratorTypes == [nil])
    }

    @Test("A lambda built in code declares the types it is given")
    func lambdaIteratorTypesInCode() {
        let body = AQLVariableExpression(name: "a")
        #expect(AQLLambdaExpression(iterator: "a", body: body).iteratorTypes == [nil])
        #expect(AQLLambdaExpression(iterator: "a", iteratorType: "Integer", body: body).iteratorTypes == ["Integer"])
        #expect(AQLLambdaExpression(iterators: ["a", "b"], body: body).iteratorTypes == [nil, nil])
        let declared = AQLLambdaExpression(iterators: ["a", "b"], iteratorTypes: ["String"], body: body)
        #expect(declared.iteratorTypes == ["String", nil])
    }
}
