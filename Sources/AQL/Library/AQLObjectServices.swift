//
//  AQLObjectServices.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Services available on every value and on model objects.
///
/// Covers `oclIsUndefined`, `oclIsKindOf`, `oclIsTypeOf`, `oclAsType`, `toString`,
/// `equals`, `lineSeparator`, and the reflective object services `eClass`, `eContainer`,
/// `eContents`, `eAllContents`, `eGet`, `eInverse`, `ancestors`, `siblings`,
/// `precedingSiblings`, `followingSiblings` and `allInstances`.
///
/// Containment queries that need to look upwards (`eContainer`, `ancestors`, `siblings`,
/// `eInverse`) search the resources registered with ``AQLExecutionContext/addResource(_:)``.
public struct AQLObjectServices: AQLServiceProvider {
    /// Creates the provider.
    public init() {}

    /// The services offered.
    public var services: [AQLService] {
        var list: [AQLService] = [
            AQLService("oclIsUndefined") { $0.receiver == nil },
            AQLService("oclIsKindOf", arity: 1, acceptsTypeArguments: true) { call in
                try call.type(0).isKind(call.receiver)
            },
            AQLService("oclIsTypeOf", arity: 1, acceptsTypeArguments: true) { call in
                try call.type(0).isType(call.receiver)
            },
            AQLService("oclAsType", arity: 1, acceptsTypeArguments: true) { call in
                _ = try call.type(0)
                return call.receiver
            },
            AQLService("toString") { AQLValues.description(of: $0.receiver) },
            AQLService("equals", arity: 1) { AQLValues.areEqual($0.receiver, $0.argument(0)) },
            AQLService("differs", arity: 1) { !AQLValues.areEqual($0.receiver, $0.argument(0)) },
            AQLService("lineSeparator") { _ in "\n" },
            AQLService("allInstances", receiver: .type) { call in
                guard let type = call.receiver as? AQLTypeDescriptor else { return nil }
                var found: [any EcoreValue] = []
                for resource in call.context.resources {
                    found.append(contentsOf: await resource.getAllObjects().filter(type.isKind))
                }
                return EcoreValueArray(found)
            },
        ]
        list += reflectiveServices
        return list
    }

    private var reflectiveServices: [AQLService] {
        let typed: (String, @escaping @MainActor @Sendable (AQLServiceCall, any EObject, AQLTypeDescriptor?) async throws -> (any EcoreValue)?)
            -> [AQLService] = { name, body in
            [
                AQLService(name, receiver: .object) { call in
                    try await body(call, call.receiver as! any EObject, nil)
                },
                AQLService(name, receiver: .object, arity: 1, acceptsTypeArguments: true) { call in
                    try await body(call, call.receiver as! any EObject, try call.type(0))
                },
            ]
        }
        let listed: (String, @escaping @MainActor @Sendable (AQLServiceCall, any EObject) async throws -> [any EcoreValue])
            -> [AQLService] = { name, body in
            typed(name) { call, object, type in
                var items = try await body(call, object)
                if let type { items = items.filter(type.isKind) }
                return EcoreValueArray(items)
            }
        }
        var list: [AQLService] = [
            AQLService("eClass", receiver: .object) { call in
                Self.classValue(of: call.receiver as! any EObject)
            },
            AQLService("eGet", receiver: .object, arity: 1) { call in
                let object = call.receiver as! any EObject
                let name = try call.string(0)
                do {
                    return try await call.context.navigate(from: object, property: name)
                } catch {
                    if let dynamic = object as? DynamicEObject { return dynamic.eGet(name) }
                    throw error
                }
            },
        ]
        list += listed("eContents") { call, object in
            try await Self.contents(of: object, in: call.context)
        }
        list += listed("eAllContents") { call, object in
            try await Self.allContents(of: object, in: call.context)
        }
        list += typed("eContainer") { call, object, type in
            var current = try await call.context.parents()[object.id]
            while let container = current {
                if type?.isKind(container) ?? true { return container }
                current = try await call.context.parents()[container.id]
            }
            return nil
        }
        list += listed("ancestors") { call, object in
            let parents = try await call.context.parents()
            var result: [any EcoreValue] = []
            var current = parents[object.id]
            while let container = current {
                result.append(container)
                current = parents[container.id]
            }
            return result
        }
        let siblingServices: [(String, @Sendable ([any EcoreValue], any EObject) -> [any EcoreValue])] = [
            ("siblings", { items, object in items.filter { !AQLValues.areEqual($0, object) } }),
            ("precedingSiblings", { items, object in
                guard let position = items.firstIndex(where: { AQLValues.areEqual($0, object) }) else { return [] }
                return Array(items[..<position])
            }),
            ("followingSiblings", { items, object in
                guard let position = items.firstIndex(where: { AQLValues.areEqual($0, object) }) else { return [] }
                return Array(items[(position + 1)...])
            }),
        ]
        for (name, select) in siblingServices {
            list += listed(name) { call, object in
                guard let parent = try await call.context.parents()[object.id] else { return [] }
                return select(try await Self.contents(of: parent, in: call.context), object)
            }
        }
        list += listed("eInverse") { call, object in
            var result: [any EcoreValue] = []
            for resource in call.context.resources {
                for candidate in await resource.getAllObjects() {
                    guard let eClass = candidate.eClass as? EClass else { continue }
                    let references = Self.orderedFeatures(of: eClass).compactMap { $0 as? EReference }
                    let refersToObject = references.contains { reference in
                        AQLValues.coerceToCollection(candidate.eGet(reference)).contains { item in
                            (item as? EUUID) == object.id || (item as? any EObject)?.id == object.id
                        }
                    }
                    if refersToObject { result.append(candidate) }
                }
            }
            return result
        }
        return list
    }

    // MARK: - Reflection Helpers

    /// The class of an object as a value.
    ///
    /// - Parameter object: The object.
    /// - Returns: The `EClass` if the object has one, otherwise a descriptor naming its metaclass.
    static func classValue(of object: any EObject) -> any EcoreValue {
        let classifier = object.eClass
        if let eClass = classifier as? EClass { return eClass }
        if let value = classifier as? any EcoreValue { return value }
        return AQLTypeDescriptor(typeName: classifier.name)
    }

    /// The structural features of a class, supertypes first, without duplicates.
    static func orderedFeatures(of eClass: EClass) -> [any EStructuralFeature] {
        var seen: Set<EUUID> = []
        var result: [any EStructuralFeature] = []
        func visit(_ current: EClass) {
            current.eSuperTypes.forEach(visit)
            for feature in current.eStructuralFeatures where seen.insert(feature.id).inserted {
                result.append(feature)
            }
        }
        visit(eClass)
        return result
    }

    /// The directly contained objects of an object, in feature order.
    ///
    /// - Parameters:
    ///   - object: The container.
    ///   - context: The execution context used to resolve references.
    /// - Returns: The contained objects.
    static func contents(of object: any EObject, in context: AQLExecutionContext) async throws
        -> [any EcoreValue]
    {
        guard let eClass = object.eClass as? EClass else { return [] }
        var result: [any EcoreValue] = []
        for feature in orderedFeatures(of: eClass) {
            guard let reference = feature as? EReference, reference.containment else { continue }
            let raw = AQLValues.coerceToCollection(object.eGet(reference))
            var unresolved = false
            for item in raw {
                if let id = item as? EUUID {
                    if let resolved = await context.resolve(id) {
                        result.append(resolved)
                    } else {
                        unresolved = true
                    }
                } else {
                    result.append(item)
                }
            }
            if unresolved,
                let viaEngine = try? await context.navigate(from: object, property: reference.name)
            {
                for item in AQLValues.coerceToCollection(viaEngine)
                where !result.contains(where: { AQLValues.areEqual($0, item) }) {
                    result.append(item)
                }
            }
        }
        return result
    }

    /// All transitively contained objects in depth-first pre-order.
    static func allContents(of object: any EObject, in context: AQLExecutionContext) async throws
        -> [any EcoreValue]
    {
        var result: [any EcoreValue] = []
        var visited: Set<EUUID> = [object.id]
        func visit(_ current: any EObject) async throws {
            for child in try await contents(of: current, in: context) {
                guard let childObject = child as? any EObject, visited.insert(childObject.id).inserted else {
                    continue
                }
                result.append(childObject)
                try await visit(childObject)
            }
        }
        try await visit(object)
        return result
    }
}
