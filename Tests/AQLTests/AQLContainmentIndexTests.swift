//
//  AQLContainmentIndexTests.swift
//  AQL
//
//  Created by Rene Hexel on 29/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import AQL

/// Moves `a2` from `a` to `b` in the resource of a tree fixture.
@MainActor
private func moveA2ToB(in t: TreeFixture) async {
    await t.resource.eSet(objectId: t.a.id, feature: "children", value: [t.a1.id])
    await t.resource.eSet(objectId: t.b.id, feature: "children", value: [t.a2.id])
}

/// A service that changes the model: `obj.moveA2ToB()` performs ``moveA2ToB(in:)``.
private struct MovingServices: AQLServiceProvider {
    let move: @MainActor @Sendable () async -> Void
    let declaresModification: Bool

    var services: [AQLService] {
        let move = self.move
        return [
            AQLService("moveA2ToB", receiver: .object, modifiesModels: declaresModification) { call in
                await move()
                return call.receiver
            }
        ]
    }
}

/// A containment query whose results are compared with and without caching.
struct ContainmentQuery: Sendable, CustomTestStringConvertible {
    let service: String
    let object: String
    let typeName: String?

    init(_ service: String, _ object: String, type typeName: String? = nil) {
        self.service = service
        self.object = object
        self.typeName = typeName
    }

    var testDescription: String {
        "\(object).\(service)(\(typeName ?? ""))"
    }

    static let all: [ContainmentQuery] = [
        .init("eContainer", "root"), .init("eContainer", "a"), .init("eContainer", "a1"),
        .init("eContainer", "a2"), .init("eContainer", "b"), .init("eContainer", "a1", type: "Node"),
        .init("eContainer", "a1", type: "Leaf"), .init("ancestors", "a1"), .init("ancestors", "root"),
        .init("ancestors", "a2", type: "Node"), .init("siblings", "a1"), .init("siblings", "b"),
        .init("siblings", "root"), .init("precedingSiblings", "a2"), .init("followingSiblings", "a1"),
    ]
}

@MainActor
@Suite("AQL containment index")
struct AQLContainmentIndexTests {
    private func object(_ name: String, in t: TreeFixture) -> DynamicEObject {
        switch name {
        case "root": t.root
        case "a": t.a
        case "a1": t.a1
        case "a2": t.a2
        default: t.b
        }
    }

    private func evaluate(_ query: ContainmentQuery, in t: TreeFixture) async throws -> [String] {
        let receiver = object(query.object, in: t)
        if let typeName = query.typeName {
            return t.names(
                try await t.call(receiver, query.service, AQLTypeLiteralExpression(packageName: nil, typeName: typeName)))
        }
        return t.names(try await t.call(receiver, query.service))
    }

    @Test("Containment queries agree with and without caching", arguments: ContainmentQuery.all)
    func cachedAndUncachedAgree(_ query: ContainmentQuery) async throws {
        let uncached = await TreeFixture(options: .standard)
        let cached = await TreeFixture(options: .standard)
        cached.context.cachesContainmentIndex = true
        let expected = try await evaluate(query, in: uncached)
        #expect(try await evaluate(query, in: cached) == expected)
        #expect(try await evaluate(query, in: cached) == expected)
    }

    @Test("With caching, each container is looked up once for repeated containment queries")
    func cachedContainersAreLookedUpOnce() async throws {
        let t = await TreeFixture(options: .standard)
        t.context.cachesContainmentIndex = true
        for _ in 0..<100 {
            _ = try await t.call(t.a1, "eContainer")
            _ = try await t.call(t.a2, "ancestors")
            _ = try await t.call(t.a1, "eContainer", AQLTypeLiteralExpression(packageName: nil, typeName: "Node"))
        }
        // a1, a2, a and root are each looked up once.
        #expect(t.context.containerLookups == 4)
    }

    @Test("Without caching, a containment query looks up only the containers it follows")
    func uncachedQueryLooksUpOnlyWhatItFollows() async throws {
        let t = await TreeFixture(options: .standard)
        _ = try await t.call(t.a1, "eContainer")
        #expect(t.context.containerLookups == 1)
        _ = try await t.call(t.a1, "ancestors")
        #expect(t.context.containerLookups == 4)
        _ = try await t.call(t.a1, "siblings")
        #expect(t.context.containerLookups == 5)
    }

    @Test("Metamodel objects find their containers with and without caching")
    func metamodelContainers() async throws {
        let t = await TreeFixture(options: .standard)
        var package = EPackage(name: "p", nsURI: "http://example.org/p", nsPrefix: "p")
        package.eClassifiers = [t.nodeClass]
        let metamodel = Resource()
        await metamodel.add(package)
        t.context.addResource(metamodel)
        let attribute = try #require(t.nodeClass.eStructuralFeatures.first as? EAttribute)
        for caches in [false, true] {
            t.context.cachesContainmentIndex = caches
            #expect((try await t.call(t.nodeClass, "eContainer") as? EPackage)?.name == "p")
            #expect((try await t.call(attribute, "eContainer") as? EClass)?.name == "Node")
        }
    }

    @Test("Without caching, containment queries see model changes immediately")
    func uncachedSeesChanges() async throws {
        let t = await TreeFixture(options: .standard)
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        await moveA2ToB(in: t)
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["b"])
        #expect(t.names(try await t.call(t.a2, "ancestors")) == ["b", "root"])
    }

    @Test("An invalidated index reflects model changes")
    func invalidationReflectsChanges() async throws {
        let t = await TreeFixture(options: .standard)
        t.context.cachesContainmentIndex = true
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        await moveA2ToB(in: t)
        t.context.invalidateContainmentIndex()
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["b"])
        #expect(t.names(try await t.call(t.a1, "siblings")) == [])
        // a2 before and after the invalidation, then a1.
        #expect(t.context.containerLookups == 3)
    }

    @Test("Switching caching off drops the cached index")
    func disablingCachingDropsIndex() async throws {
        let t = await TreeFixture(options: .standard)
        t.context.cachesContainmentIndex = true
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        await moveA2ToB(in: t)
        t.context.cachesContainmentIndex = false
        t.context.cachesContainmentIndex = true
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["b"])
    }

    @Test("Adding a resource drops the cached index")
    func addingResourceDropsIndex() async throws {
        let t = await TreeFixture(options: .standard)
        t.context.cachesContainmentIndex = true
        #expect(try await t.call(t.root, "eContainer") == nil)
        var holder = DynamicEObject(eClass: t.nodeClass)
        holder.eSet("name", value: "holder")
        holder.eSet("children", value: [t.root.id])
        let other = Resource()
        await other.add(holder)
        t.context.addResource(other)
        #expect(t.names(try await t.call(t.root, "eContainer")) == ["holder"])
    }

    @Test("A service declared to modify models drops the cached index")
    func modifyingServiceDropsIndex() async throws {
        let t = await TreeFixture(options: .standard)
        t.context.cachesContainmentIndex = true
        t.context.register(MovingServices(move: { await moveA2ToB(in: t) }, declaresModification: true))
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["a"])
        _ = try await t.call(t.a2, "moveA2ToB")
        #expect(t.names(try await t.call(t.a2, "eContainer")) == ["b"])
        #expect(t.names(try await t.call(t.a2, "ancestors")) == ["b", "root"])
    }

    @Test("Services do not modify models unless they declare it")
    func servicesArePureByDefault() {
        let service = AQLService("pure") { _ in nil }
        #expect(!service.modifiesModels)
        #expect(AQLService("changing", modifiesModels: true) { _ in nil }.modifiesModels)
        #expect(AQLService("changing", arity: 1, modifiesModels: true) { _ in nil }.modifiesModels)
        #expect(AQLService("changing", modifiesModels: true) { _ in nil }.aliased(as: "alias").modifiesModels)
    }

    @Test("Services created with the initialisers of version 0.6 do not modify models")
    func earlierServiceInitialisers() {
        typealias RangeInitialiser = (
            String, AQLReceiver, ClosedRange<Int>, Bool, @escaping AQLServiceImplementation
        ) -> AQLService
        typealias CountInitialiser = (
            String, AQLReceiver, Int, Bool, @escaping AQLServiceImplementation
        ) -> AQLService
        let range: RangeInitialiser = AQLService.init(_:receiver:arity:acceptsTypeArguments:implementation:)
        let count: CountInitialiser = AQLService.init(_:receiver:arity:acceptsTypeArguments:implementation:)
        let services = [range("r", .any, 0...1, false) { _ in nil }, count("c", .any, 2, true) { _ in nil }]
        #expect(services.map(\.arity) == [0...1, 2...2])
        #expect(services.allSatisfy { !$0.modifiesModels })
    }

    @Test("Objects held by another resource find their container")
    func crossResourceContainment() async throws {
        let t = await TreeFixture(options: .standard)
        var child = DynamicEObject(eClass: t.leafClass)
        child.eSet("name", value: "c")
        let other = Resource()
        await other.add(child)
        await t.resource.eSet(objectId: t.b.id, feature: "children", value: [child.id])
        t.context.addResource(other)
        for caches in [false, true] {
            t.context.cachesContainmentIndex = caches
            #expect(t.names(try await t.call(child, "eContainer")) == ["b"])
            #expect(t.names(try await t.call(child, "ancestors")) == ["b", "root"])
        }
    }
}
