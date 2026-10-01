//
//  AQLServiceRegistrationTests.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

private struct GreetingServices: AQLServiceProvider {
    var services: [AQLService] {
        [
            AQLService("greet", receiver: .string, arity: 1) { call in
                "\(try call.string(0)), \(try call.receiverString())"
            },
            AQLService("answer", receiver: .standalone) { _ in 42 },
            AQLService("describe", receiver: .any, arity: 0...2) { call in
                "\(call.arguments.count)"
            },
            AQLService("delayed", receiver: .number, arity: 1) { call in
                try await Task.sleep(for: .milliseconds(5))
                return try call.integer(0) + (AQLValues.integer(call.receiver) ?? 0)
            },
            AQLService("typeName", receiver: .any, arity: 1, acceptsTypeArguments: true) { call in
                try call.type(0).qualifiedName
            },
        ]
    }
}

private struct OverridingServices: AQLServiceProvider {
    var services: [AQLService] {
        [
            AQLService("toUpper", receiver: .string) { _ in "overridden" },
            AQLService("size", receiver: .string) { _ in -1 },
            AQLService("derived", receiver: .object) { _ in "derived value" },
        ]
    }
}

@MainActor
@Suite("AQL service registration")
struct AQLServiceRegistrationTests {
    private func run(_ expression: any AQLExpression, providers: [any AQLServiceProvider]) async throws
        -> (any EcoreValue)?
    {
        let context = AQLExecutionContext(
            executionEngine: ECoreExecutionEngine(models: [:]), serviceProviders: providers)
        return try await expression.evaluate(in: context)
    }

    @Test("Receiver and arguments are passed to the service")
    func argumentPassing() async throws {
        let result = try await run(
            AQLCallExpression(source: lit("World"), methodName: "greet", arguments: [lit("Hello")]),
            providers: [GreetingServices()])
        #expect(result as? String == "Hello, World")
    }

    @Test("Standalone services need no receiver")
    func standalone() async throws {
        let result = try await run(AQLCallExpression(methodName: "answer"), providers: [GreetingServices()])
        #expect(result as? Int == 42)
    }

    @Test("Arity ranges select the service", arguments: [0, 1, 2])
    func arityRange(_ count: Int) async throws {
        let result = try await run(
            AQLCallExpression(source: lit(nil), methodName: "describe", arguments: Array(repeating: lit(1), count: count)),
            providers: [GreetingServices()])
        #expect(result as? String == "\(count)")
    }

    @Test("Services may suspend")
    func asynchronous() async throws {
        let result = try await run(
            AQLCallExpression(source: lit(2), methodName: "delayed", arguments: [lit(3)]),
            providers: [GreetingServices()])
        #expect(result as? Int == 5)
    }

    @Test("Type arguments arrive as descriptors")
    func typeArguments() async throws {
        let bare = try await run(
            AQLCallExpression(source: lit(1), methodName: "typeName", arguments: [AQLVariableExpression(name: "ecore::EClass")]),
            providers: [GreetingServices()])
        #expect(bare as? String == "ecore::EClass")
        let literal = try await run(
            AQLCallExpression(source: lit(1), methodName: "typeName", arguments: [AQLTypeLiteralExpression(packageName: "p", typeName: "T")]),
            providers: [GreetingServices()])
        #expect(literal as? String == "p::T")
    }

    @Test("Client services override the standard library")
    func overriding() async throws {
        let upper = try await run(
            AQLCallExpression(source: lit("a"), methodName: "toUpper"), providers: [OverridingServices()])
        #expect(upper as? String == "overridden")
        let lower = try await run(
            AQLCallExpression(source: lit("A"), methodName: "toLower"), providers: [OverridingServices()])
        #expect(lower as? String == "a")
    }

    @Test("The most recent registration wins")
    func registrationOrder() async throws {
        struct First: AQLServiceProvider {
            var services: [AQLService] { [AQLService("which", receiver: .any) { _ in "first" }] }
        }
        struct Second: AQLServiceProvider {
            var services: [AQLService] { [AQLService("which", receiver: .any) { _ in "second" }] }
        }
        let context = makeContext()
        context.register(First())
        context.register(Second())
        let result = try await AQLCallExpression(source: lit(1), methodName: "which").evaluate(in: context)
        #expect(result as? String == "second")
    }

    @Test("Services can use the context to navigate")
    func contextAccess() async throws {
        struct Navigating: AQLServiceProvider {
            var services: [AQLService] {
                [AQLService("nameOf", receiver: .object) { call in
                    try await call.context.navigate(from: call.receiver, property: "name")
                }]
            }
        }
        var node = EClass(name: "N")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: EDataType(name: "EString")))
        var object = DynamicEObject(eClass: node)
        object.eSet("name", value: "n1")
        let result = try await run(
            AQLCallExpression(source: lit(object), methodName: "nameOf"), providers: [Navigating()])
        #expect(result as? String == "n1")
    }

    @Test("Registered zero-argument services answer property-style navigation")
    func navigationFallback() async throws {
        let engine = ECoreExecutionEngine(models: [:])
        let context = AQLExecutionContext(executionEngine: engine, serviceProviders: [OverridingServices()])
        let object = DynamicEObject(eClass: EClass(name: "N"))
        let result = try await AQLNavigationExpression(source: lit(object), property: "derived").evaluate(in: context)
        #expect(result as? String == "derived value")
        await #expect(throws: (any Error).self) {
            _ = try await AQLNavigationExpression(source: lit(object), property: "missing").evaluate(in: context)
        }
    }

    @Test("Unknown services are reported")
    func unknown() async throws {
        await #expect(throws: AQLExecutionError.self) {
            _ = try await run(AQLCallExpression(source: lit("a"), methodName: "nonsense"), providers: [])
        }
        await #expect(throws: AQLExecutionError.self) {
            _ = try await run(
                AQLCallExpression(source: lit(DynamicEObject(eClass: EClass(name: "N"))), methodName: "op", arguments: [lit(1)]),
                providers: [])
        }
    }

    @Test("Zero-argument call on an object falls back to the structural feature")
    func featureFallback() async throws {
        var node = EClass(name: "N")
        node.eStructuralFeatures.append(EAttribute(name: "label", eType: EDataType(name: "EString")))
        var object = DynamicEObject(eClass: node)
        object.eSet("label", value: "L")
        let result = try await run(AQLCallExpression(source: lit(object), methodName: "label"), providers: [])
        #expect(result as? String == "L")
    }

    @Test("Standard library can be omitted from a registry")
    func emptyRegistry() {
        let registry = AQLServiceRegistry(includingStandardLibrary: false)
        #expect(registry.find(name: "size", receiver: "a", hasReceiver: true, argumentCount: 0) == nil)
        let full = AQLServiceRegistry()
        #expect(full.find(name: "size", receiver: "a", hasReceiver: true, argumentCount: 0) != nil)
    }

    @Test("Receiver requirements")
    func receivers() {
        #expect(AQLReceiver.nonNull.matches(nil, hasReceiver: true) == false)
        #expect(AQLReceiver.any.matches(nil, hasReceiver: true))
        #expect(AQLReceiver.any.matches(nil, hasReceiver: false) == false)
        #expect(AQLReceiver.standalone.matches(nil, hasReceiver: false))
        #expect(AQLReceiver.custom { $0 is Int }.matches(1, hasReceiver: true))
        #expect(AQLReceiver.type.matches(AQLTypeDescriptor(typeName: "T"), hasReceiver: true))
        #expect(AQLReceiver.boolean.matches(true, hasReceiver: true))
        #expect(AQLReceiver.string.matches(1, hasReceiver: true) == false)
    }

    @Test("Alias creates an equivalent service")
    func alias() async throws {
        let original = AQLService("one", receiver: .any) { _ in 1 }
        let copy = original.aliased(as: "uno")
        #expect(copy.name == "uno")
        let result = try await copy.implementation(
            AQLServiceCall(name: "uno", receiver: nil, arguments: [], context: makeContext()))
        #expect(result as? Int == 1)
    }

    @Test("Service call accessors report type errors")
    func accessors() async throws {
        let call = AQLServiceCall(name: "x", receiver: 1, arguments: ["s"], context: makeContext())
        #expect(throws: AQLExecutionError.self) { try call.receiverString() }
        #expect(throws: AQLExecutionError.self) { try call.integer(0) }
        #expect(throws: AQLExecutionError.self) { try call.string(3) }
        #expect(throws: AQLExecutionError.self) { try call.lambda(0) }
        #expect(throws: AQLExecutionError.self) { try call.type(0) }
        #expect(call.argument(7) == nil)
    }

    @Test("Unset derived, volatile and transient features fall through to a zero-argument service")
    func computedFeatureFallback() async throws {
        struct Computing: AQLServiceProvider {
            var services: [AQLService] {
                ["computed", "volatileOne", "transientOne", "plain"].map { name in
                    AQLService(name, receiver: .object) { _ in "service" }
                }
            }
        }
        var node = EClass(name: "N")
        let string = EDataType(name: "EString")
        node.eStructuralFeatures.append(EAttribute(name: "computed", eType: string, derived: true))
        node.eStructuralFeatures.append(EAttribute(name: "volatileOne", eType: string, volatile: true))
        node.eStructuralFeatures.append(EAttribute(name: "transientOne", eType: string, transient: true))
        node.eStructuralFeatures.append(EAttribute(name: "plain", eType: string))
        var object = DynamicEObject(eClass: node)
        let context = AQLExecutionContext(
            executionEngine: ECoreExecutionEngine(models: [:]), serviceProviders: [Computing()])
        func navigate(_ property: String) async throws -> (any EcoreValue)? {
            try await AQLNavigationExpression(source: lit(object), property: property).evaluate(in: context)
        }
        #expect(try await navigate("computed") as? String == "service")
        #expect(try await navigate("volatileOne") as? String == "service")
        #expect(try await navigate("transientOne") as? String == "service")
        #expect(try await navigate("plain") == nil)

        object.eSet("computed", value: "stored")
        let withValue = AQLExecutionContext(
            executionEngine: ECoreExecutionEngine(models: [:]), serviceProviders: [Computing()])
        let stored = try await AQLNavigationExpression(source: lit(object), property: "computed")
            .evaluate(in: withValue)
        #expect(stored as? String == "stored")
    }
}
