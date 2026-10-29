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
/// collections are kept as elements, not flattened. The value is a collection
/// of the literal's kind; ordered sets and sets leave out repeated elements.
/// While ``AQLOptions/collectionKinds`` is ``AQLCollectionKinds/sequences``, the
/// value is a sequence (still without the repeated elements of an ordered set or set).
public struct AQLCollectionLiteralExpression: AQLExpression {
    /// Where the expression was written, if known.
    public let origin: SourceOrigin

    /// The kind of collection.
    ///
    /// The literal kinds are the collection kinds of the values they create.
    public typealias Kind = EcoreCollectionKind

    /// The kind of collection.
    public let kind: Kind

    /// The element expressions.
    public let elements: [any AQLExpression]

    /// Creates a collection literal.
    ///
    /// - Parameters:
    ///   - kind: The collection kind.
    ///   - elements: The element expressions.
    ///   - origin: Where the expression was written, if known.
    public init(kind: Kind, elements: [any AQLExpression], origin: SourceOrigin = .init()) {
        self.origin = origin
        self.kind = kind
        self.elements = elements
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        var values: [any EcoreValue] = []
        for element in elements {
            if let value = try await element.evaluate(in: context) { values.append(value) }
        }
        return context.collection(values, kind: kind)
    }
}
