import ECore
import EMFBase
import Testing

@testable import AQL

@MainActor
struct AQLTests {

    @Test func testVariableEvaluation() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine)

        context.setVariable("foo", value: "bar")

        let expr = AQLVariableExpression(name: "foo")
        let result = try await expr.evaluate(in: context)

        #expect(result as? String == "bar")
    }

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
}
