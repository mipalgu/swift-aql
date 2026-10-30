//
//  AQLContainerScopeTests.swift
//  AQL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import AQL

/// A parent in one resource whose child belongs to another resource of the same set.
///
/// The resource of the parent finds the container of the child only in the
/// ``ContainerLookupScope/anyResource`` scope, so the answers of the containment services
/// reveal the scope that the resource uses.
@MainActor
private struct SplitFixture {
    let set: ResourceSet
    let containers: Resource
    let children: Resource
    let child: DynamicEObject
    let sibling: DynamicEObject

    init(defaultScope: ContainerLookupScope? = nil) async {
        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: EDataType(name: "EString")))
        node.eStructuralFeatures.append(
            EReference(name: "children", eType: node, upperBound: -1, containment: true))
        func make(_ name: String) -> DynamicEObject {
            var object = DynamicEObject(eClass: node)
            object.eSet("name", value: name)
            return object
        }
        var parent = make("parent")
        child = make("child")
        sibling = make("sibling")
        parent.eSet("children", value: [child.id, sibling.id])
        set = ResourceSet(defaultContainerLookupScope: defaultScope)
        containers = await set.createResource(uri: "test://aql-scope-containers")
        children = await set.createResource(uri: "test://aql-scope-children")
        await containers.add(parent)
        await children.add(contentsOf: [child, sibling])
    }

    /// A context with the given options, caching and both resources.
    func context(_ options: AQLOptions, caching: Bool = false) -> AQLExecutionContext {
        let context = makeContext(options: options)
        context.cachesContainmentIndex = caching
        for resource in [containers, children] { context.addResource(resource) }
        return context
    }

    /// Calls a containment service on the child and names the objects it yields.
    func call(_ service: String, in context: AQLExecutionContext) async throws -> [String] {
        let value = try await AQLCallExpression(source: lit(child), methodName: service).evaluate(in: context)
        return AQLValues.coerceToCollection(value).compactMap { ($0 as? DynamicEObject)?.eGet("name") as? String }
    }
}

@MainActor
@Suite("AQL container lookup scope")
struct AQLContainerScopeTests {

    @Test("Without a configured scope, the resources answer for any resource as released", arguments: [false, true])
    func unconfigured(_ caching: Bool) async throws {
        let t = await SplitFixture()
        let context = t.context(.standard, caching: caching)
        #expect(try await t.call("eContainer", in: context) == ["parent"])
        #expect(try await t.call("ancestors", in: context) == ["parent"])
        #expect(try await t.call("siblings", in: context) == ["sibling"])
    }

    @Test("A resource answers in the scope configured for its set", arguments: [false, true])
    func configuredSet(_ caching: Bool) async throws {
        let anywhere = await SplitFixture(defaultScope: .anyResource)
        #expect(try await anywhere.call("eContainer", in: anywhere.context(.standard, caching: caching)) == ["parent"])
        let local = await SplitFixture(defaultScope: .thisResource)
        let context = local.context(.standard, caching: caching)
        #expect(try await local.call("eContainer", in: context) == [])
        #expect(try await local.call("ancestors", in: context) == [])
        #expect(try await local.call("siblings", in: context) == [])
    }

    @Test("A resource answers in its own configured scope")
    func configuredResource() async throws {
        let t = await SplitFixture(defaultScope: .anyResource)
        await t.containers.setContainerLookupScope(.thisResource)
        #expect(try await t.call("eContainer", in: t.context(.standard)) == [])
        await t.containers.setContainerLookupScope(.anyResource)
        await t.set.setDefaultContainerLookupScope(.thisResource)
        #expect(try await t.call("eContainer", in: t.context(.standard)) == ["parent"])
    }

    @Test("Containers among registered objects do not depend on the scope", arguments: ContainerLookupScope.allCases)
    func registeredObjectsIgnoreScope(_ scope: ContainerLookupScope) async throws {
        let t = await SplitFixture(defaultScope: scope)
        let context = t.context(.legacy)
        #expect(try await t.call("eContainer", in: context) == ["parent"])
        #expect(try await t.call("siblings", in: context) == ["sibling"])
    }
}
