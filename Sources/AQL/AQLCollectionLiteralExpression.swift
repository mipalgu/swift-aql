//
//  AQLCollectionLiteralExpression.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// A collection literal such as `Sequence{a, b}` or `OrderedSet{x}`.
///
/// Elements keep their runtime values (objects stay objects). Nested
/// collections are kept as elements, not flattened.
public struct AQLCollectionLiteralExpression: AQLExpression {
    /// The kind of collection.
    public enum Kind: String, Sendable {
        /// An ordered collection that may contain duplicates.
        case sequence = "Sequence"
        /// An ordered collection without duplicates.
        case orderedSet = "OrderedSet"
        /// An unordered collection without duplicates (held in insertion order).
        case set = "Set"
        /// A collection that may contain duplicates (held in insertion order).
        case bag = "Bag"
    }

    /// The kind of collection.
    public let kind: Kind

    /// The element expressions.
    public let elements: [any AQLExpression]

    /// Creates a collection literal.
    ///
    /// - Parameters:
    ///   - kind: The collection kind.
    ///   - elements: The element expressions.
    public init(kind: Kind, elements: [any AQLExpression]) {
        self.kind = kind
        self.elements = elements
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        var values: [any EcoreValue] = []
        for element in elements {
            if let value = try await element.evaluate(in: context) { values.append(value) }
        }
        switch kind {
        case .sequence, .bag: return EcoreValueArray(values)
        case .orderedSet, .set: return EcoreValueArray(AQLValues.distinct(values))
        }
    }
}
