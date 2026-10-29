//
//  AQLContainerLookupTests.swift
//  AQL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// Models in which the two container lookups give different answers.
///
/// A metamodel resource holds a package whose class nests an attribute. One resource holds
/// two holders `h1` and `h2` that both claim `c`, with `h2` also holding `d`. Two further
/// resources hold `g1` and `g2`, which both claim `e`, held by the first of them.
@MainActor
struct ContainerLookupFixture {
    let node: EClass
    let attribute: EAttribute
    let metamodel: Resource
    let objects: [String: DynamicEObject]
    let shared: Resource
    let first: Resource
    let second: Resource

    init() async {
        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: EDataType(name: "EString")))
        node.eStructuralFeatures.append(
            EReference(name: "children", eType: node, upperBound: -1, containment: true))
        func make(_ name: String) -> DynamicEObject {
            var object = DynamicEObject(eClass: node)
            object.eSet("name", value: name)
            return object
        }
        var package = EPackage(name: "p", nsURI: "http://example.org/p", nsPrefix: "p")
        package.eClassifiers = [node]
        metamodel = Resource()
        await metamodel.add(package)
        var h1 = make("h1"), h2 = make("h2"), g1 = make("g1"), g2 = make("g2")
        let c = make("c"), d = make("d"), e = make("e")
        h1.eSet("children", value: [c.id])
        h2.eSet("children", value: [d.id, c.id])
        g1.eSet("children", value: [e.id])
        g2.eSet("children", value: [e.id])
        shared = Resource()
        for object in [h1, h2, c, d] { await shared.add(object) }
        first = Resource()
        for object in [g1, e] { await first.add(object) }
        second = Resource()
        await second.add(g2)
        self.node = node
        self.attribute = node.eStructuralFeatures.first as! EAttribute
        objects = Dictionary(uniqueKeysWithValues: [h1, h2, c, d, g1, g2, e].map { ($0.eGet("name") as! String, $0) })
    }

    /// A context with the given options, caching and all resources of the fixture.
    func context(_ options: AQLOptions, caching: Bool) -> AQLExecutionContext {
        let context = makeContext(options: options)
        context.cachesContainmentIndex = caching
        for resource in [metamodel, shared, first, second] { context.addResource(resource) }
        return context
    }

    /// The names of the objects, packages and classes in a value.
    static func names(_ value: (any EcoreValue)?) -> [String] {
        AQLValues.coerceToCollection(value).compactMap { item in
            if let object = item as? DynamicEObject { return object.eGet("name") as? String }
            if let package = item as? EPackage { return package.name }
            if let eClass = item as? EClass { return eClass.name }
            return nil
        }
    }

    /// Calls a containment service on a receiver.
    func call(_ receiver: any EcoreValue, _ service: String, in context: AQLExecutionContext) async throws -> [String] {
        Self.names(try await AQLCallExpression(source: lit(receiver), methodName: service).evaluate(in: context))
    }

    /// Calls a containment service on a named object.
    func call(_ name: String, _ service: String, in context: AQLExecutionContext) async throws -> [String] {
        try await call(objects[name]!, service, in: context)
    }
}

@MainActor
@Suite("AQL container lookup")
struct AQLContainerLookupTests {

    @Test("Containers among registered objects are those of version 0.6.1", arguments: [false, true])
    func registeredObjects(_ caching: Bool) async throws {
        let t = await ContainerLookupFixture()
        for options in [AQLOptions.legacy, AQLOptions(containerLookup: .registeredObjects)] {
            let context = t.context(options, caching: caching)
            #expect(try await t.call(t.node, "eContainer", in: context) == ["p"])
            #expect(try await t.call(t.attribute, "eContainer", in: context) == [])
            #expect(try await t.call(t.attribute, "ancestors", in: context) == [])
            #expect(try await t.call(t.attribute, "siblings", in: context) == [])
            #expect(try await t.call("c", "eContainer", in: context) == ["h2"])
            #expect(try await t.call("c", "ancestors", in: context) == ["h2"])
            #expect(try await t.call("c", "siblings", in: context) == ["d"])
            #expect(try await t.call("c", "precedingSiblings", in: context) == ["d"])
            #expect(try await t.call("e", "eContainer", in: context) == ["g2"])
            #expect(try await t.call("e", "ancestors", in: context) == ["g2"])
            #expect(try await t.call("g1", "eContainer", in: context) == [])
        }
    }

    @Test("Containers from the resources include nested metamodel contents", arguments: [false, true])
    func resources(_ caching: Bool) async throws {
        let t = await ContainerLookupFixture()
        for options in [AQLOptions.standard, AQLOptions(containerLookup: .resources)] {
            let context = t.context(options, caching: caching)
            #expect(try await t.call(t.node, "eContainer", in: context) == ["p"])
            #expect(try await t.call(t.attribute, "eContainer", in: context) == ["Node"])
            #expect(try await t.call(t.attribute, "ancestors", in: context) == ["Node", "p"])
            #expect(try await t.call("c", "eContainer", in: context) == ["h1"])
            #expect(try await t.call("c", "ancestors", in: context) == ["h1"])
            #expect(try await t.call("c", "siblings", in: context) == [])
            #expect(try await t.call("e", "eContainer", in: context) == ["g1"])
            #expect(try await t.call("g1", "eContainer", in: context) == [])
        }
    }

    @Test("Changing the container lookup drops the cached containers")
    func changingLookupDropsCache() async throws {
        let t = await ContainerLookupFixture()
        let context = t.context(.legacy, caching: true)
        #expect(try await t.call("c", "eContainer", in: context) == ["h2"])
        context.options.containerLookup = .resources
        #expect(try await t.call("c", "eContainer", in: context) == ["h1"])
        context.options.containerLookup = .registeredObjects
        #expect(try await t.call("c", "eContainer", in: context) == ["h2"])
    }

    @Test("Among registered objects, a cached index reflects changes only after invalidation")
    func registeredObjectsCacheInvalidation() async throws {
        let t = await TreeFixture()
        t.context.cachesContainmentIndex = true
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        await t.resource.eSet(objectId: t.a.id, feature: "children", value: [t.a1.id])
        await t.resource.eSet(objectId: t.b.id, feature: "children", value: [t.a2.id])
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        t.context.invalidateContainmentIndex()
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["b"])
        #expect(t.names(try await t.call(t.a2, "ancestors")) == ["b", "root"])
    }

    @Test("Among registered objects, an uncached query sees changes immediately")
    func registeredObjectsWithoutCache() async throws {
        let t = await TreeFixture()
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        await t.resource.eSet(objectId: t.a.id, feature: "children", value: [t.a1.id])
        await t.resource.eSet(objectId: t.b.id, feature: "children", value: [t.a2.id])
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["b"])
        #expect(t.names(try await t.call(t.a1, "siblings")) == [])
    }
}
