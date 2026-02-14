import ECore
import EMFBase
import Testing

@testable import AQL

@MainActor
struct AQLTests {

    // MARK: - Variable Evaluation

    @Test func testVariableEvaluation() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("foo", value: "bar")

        let expr = AQLVariableExpression(name: "foo")
        let result = try await expr.evaluate(in: context)

        #expect(result as? String == "bar")
    }

    // MARK: - String Interpolation

    @Test func testStringInterpolation() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("name", value: "World")

        // 'Hello ${name}!'
        let expr = AQLStringInterpolationExpression(parts: [
            .init(literal: "Hello "),
            .init(literal: "", expression: AQLVariableExpression(name: "name")),
            .init(literal: "!"),
        ])

        let result = try await expr.evaluate(in: context)

        #expect(result as? String == "Hello World!")
    }

    // MARK: - oclIsUndefined

    @Test func testOclIsUndefinedWithNilSource() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("nullVar", value: nil)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "nullVar"),
            methodName: "oclIsUndefined"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testOclIsUndefinedWithNonNilSource() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("value", value: "test")

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "value"),
            methodName: "oclIsUndefined"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == false)
    }

    // MARK: - Navigation

    @Test func testNavigateWithNilSource() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let result = try await context.navigate(from: nil, property: "name")

        #expect(result == nil)
    }

    @Test func testNavigateWithNonEObjectSource() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let result = try await context.navigate(from: "string", property: "name")

        #expect(result == nil)
    }

    // MARK: - OCL Type Operations

    @Test func testOclIsKindOfWithDynamicObject() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        // Create a simple EClass
        let personClass = EClass(name: "Person")
        let obj = DynamicEObject(eClass: personClass)

        context.setVariable("obj", value: obj)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "obj"),
            methodName: "oclIsKindOf",
            arguments: [AQLVariableExpression(name: "Person")]
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testOclIsTypeOfWithDynamicObject() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let personClass = EClass(name: "Person")
        let obj = DynamicEObject(eClass: personClass)

        context.setVariable("obj", value: obj)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "obj"),
            methodName: "oclIsTypeOf",
            arguments: [AQLVariableExpression(name: "Person")]
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testOclAsType() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let personClass = EClass(name: "Person")
        let obj = DynamicEObject(eClass: personClass)

        context.setVariable("obj", value: obj)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "obj"),
            methodName: "oclAsType",
            arguments: [AQLVariableExpression(name: "Person")]
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? DynamicEObject != nil)
    }

    // MARK: - String Operations

    @Test func testStringSize() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("str", value: "hello")

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "str"),
            methodName: "size"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Int == 5)
    }

    @Test func testStringReplace() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("str", value: "hello world")

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "str"),
            methodName: "replace",
            arguments: [
                AQLLiteralExpression(value: "world"),
                AQLLiteralExpression(value: "Swift"),
            ]
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? String == "hello Swift")
    }

    @Test func testStringUpperCase() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("str", value: "hello")

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "str"),
            methodName: "toUpperCase"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? String == "HELLO")
    }

    // MARK: - Collection Operations

    @Test func testCollectionSize() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let collection = ["a", "b", "c"]
        context.setVariable("col", value: collection)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "col"),
            methodName: "size"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Int == 3)
    }

    @Test func testCollectionIsEmpty() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let collection: [String] = []
        context.setVariable("col", value: collection)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "col"),
            methodName: "isEmpty"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testCollectionFirst() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let collection = ["first", "second", "third"]
        context.setVariable("col", value: collection)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "col"),
            methodName: "first"
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? String == "first")
    }

    @Test func testCollectionIndexOf() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let collection = ["a", "b", "c"]
        context.setVariable("col", value: collection)

        let expr = AQLCallExpression(
            source: AQLVariableExpression(name: "col"),
            methodName: "indexOf",
            arguments: [AQLLiteralExpression(value: "b")]
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Int == 1)
    }

    // MARK: - Binary Operations

    @Test func testNotEqualOperator() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLBinaryExpression(
            left: AQLLiteralExpression(value: "a"),
            op: .notEquals,
            right: AQLLiteralExpression(value: "b")
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testEqualOperator() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLBinaryExpression(
            left: AQLLiteralExpression(value: "a"),
            op: .equals,
            right: AQLLiteralExpression(value: "a")
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testAndOperator() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLBinaryExpression(
            left: AQLLiteralExpression(value: true),
            op: .and,
            right: AQLLiteralExpression(value: true)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testOrOperator() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLBinaryExpression(
            left: AQLLiteralExpression(value: false),
            op: .or,
            right: AQLLiteralExpression(value: true)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testImpliesOperator() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLBinaryExpression(
            left: AQLLiteralExpression(value: true),
            op: .implies,
            right: AQLLiteralExpression(value: false)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == false)
    }

    @Test func testNotEqualWithNil() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("nullVar", value: nil)

        let expr = AQLBinaryExpression(
            left: AQLVariableExpression(name: "nullVar"),
            op: .notEquals,
            right: AQLLiteralExpression(value: "something")
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    // MARK: - Unary Operators

    @Test func testNotOperatorTrue() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLUnaryExpression(
            op: .not,
            operand: AQLLiteralExpression(value: true)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == false)
    }

    @Test func testNotOperatorFalse() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLUnaryExpression(
            op: .not,
            operand: AQLLiteralExpression(value: false)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testNotOperatorWithNil() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLUnaryExpression(
            op: .not,
            operand: AQLLiteralExpression(value: nil)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result == nil)
    }

    @Test func testNotOperatorNested() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        // not (not true) should be true
        let expr = AQLUnaryExpression(
            op: .not,
            operand: AQLUnaryExpression(
                op: .not,
                operand: AQLLiteralExpression(value: true)
            )
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == true)
    }

    @Test func testNegateInteger() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLUnaryExpression(
            op: .negate,
            operand: AQLLiteralExpression(value: 42)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Int == -42)
    }

    @Test func testNegateDouble() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLUnaryExpression(
            op: .negate,
            operand: AQLLiteralExpression(value: 3.14)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Double == -3.14)
    }

    @Test func testNegateNil() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        let expr = AQLUnaryExpression(
            op: .negate,
            operand: AQLLiteralExpression(value: nil)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result == nil)
    }

    @Test func testNotOperatorInBinaryExpression() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        // not true and false should be false
        let expr = AQLBinaryExpression(
            left: AQLUnaryExpression(
                op: .not,
                operand: AQLLiteralExpression(value: true)
            ),
            op: .and,
            right: AQLLiteralExpression(value: false)
        )

        let result = try await expr.evaluate(in: context)

        #expect(result as? Bool == false)
    }
}
