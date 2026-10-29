//
//  AQLCollectionServices.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The AQL collection library (sequences, ordered sets, sets and bags).
///
/// The `.` and `->` call forms reach the same implementations. Collections are held as
/// `EcoreValueArray` and carry their ``EcoreCollectionKind``. Every kind keeps its elements in
/// order; ordered sets and sets hold each element at most once, sequences and bags may repeat
/// elements. An arrow call on a value that is not a collection sees a set holding that value
/// (an empty set for null). Positions are 1-based as in AQL (`at`, `insertAt`, `subSequence`,
/// `subOrderedSet`, `indexOf`, `lastIndexOf`); `indexOf` and `lastIndexOf` return 0 when the
/// element is absent. Clearing ``AQLExecutionContext/usesOneBasedIndexOf`` makes those two
/// 0-based (-1 if absent) instead.
///
/// Transformations yield a collection of the receiver's kind, so that, for example, selecting
/// from or collecting over an ordered set yields an ordered set. The exceptions are the
/// conversions (`asSequence`, `asOrderedSet`, `asSet`, `asBag`), which yield their named kind,
/// `sep`, which yields a sequence, and `closure`, which yields an ordered set for an ordered
/// receiver and a set otherwise. `union` leaves out repeated elements for every kind.
///
/// `including`, `append`, `prepend` and `insertAt` add their argument as one element, so a
/// collection argument becomes a nested collection, and a null argument adds nothing. With
/// ``AQLCollectionArguments/firstElement`` as the ``AQLOptions/collectionArguments`` of the
/// context, `including`, `append` and `prepend` add only the first element of a collection
/// argument instead. A sequence
/// or bag gains the element even if it already holds an equal one. For an ordered set or a set,
/// `including` keeps an element already present where it is, while `append`, `prepend` and
/// `insertAt` move it to the end, the front or the given position, respectively.
///
/// While the ``AQLOptions/collectionKinds`` of the context are
/// ``AQLCollectionKinds/sequences``, every collection behaves as, and every result is, a
/// sequence; `asOrderedSet` and `asSet` still leave out repeated elements.
///
/// Queries: `size`, `isEmpty`, `notEmpty`, `first`, `last`, `at`, `indexOf`, `lastIndexOf`,
/// `includes` (`contains`), `excludes`, `includesAll`, `excludesAll`, `count`, `sum`, `min`, `max`,
/// `isUnique`, `one`, `exists`, `forAll`, `any`.
///
/// Transformations: `including`, `excluding`, `union`, `intersection`, `sub` (`difference`,
/// `removeAll`), `concat` (`addAll`, `+`), `append`, `prepend`, `insertAt`, `reverse`, `flatten`,
/// `asSet`, `asOrderedSet`, `asSequence`, `asBag`, `drop`, `dropRight`, `subSequence`,
/// `subOrderedSet`, `sep`, `filter`, `sortedBy`, `select`, `reject`, `collect`, `closure`.
public struct AQLCollectionServices: AQLServiceProvider {
    /// Creates the provider.
    public init() {}

    // MARK: - Helpers

    private static func isTrue(_ value: (any EcoreValue)?) -> Bool { (value as? Bool) == true }

    private static func contains(_ items: [any EcoreValue], _ value: (any EcoreValue)?) -> Bool {
        items.contains { AQLValues.areEqual($0, value) }
    }

    @MainActor
    private static func evaluate(
        _ call: AQLServiceCall, _ element: any EcoreValue
    ) async throws -> (any EcoreValue)? {
        try await call.lambda(0).invoke(element, in: call.context)
    }

    /// The elements as a collection of the kind of the call's receiver.
    @MainActor
    private static func result(_ items: [any EcoreValue], of call: AQLServiceCall) -> EcoreValueArray {
        call.context.collection(items, kind: call.receiverKind)
    }

    @MainActor
    private static func filter(_ call: AQLServiceCall, keeping: Bool) async throws -> EcoreValueArray {
        var result: [any EcoreValue] = []
        for element in call.receiverElements() {
            if isTrue(try await evaluate(call, element)) == keeping { result.append(element) }
        }
        return Self.result(result, of: call)
    }

    /// The argument of an element-adding service as at most one element.
    ///
    /// A collection argument is kept whole (as a nested collection), or reduced to its first
    /// element, as the ``AQLOptions/collectionArguments`` of the context say; null adds
    /// nothing, as collections cannot hold null.
    @MainActor
    private static func single(_ call: AQLServiceCall) -> [any EcoreValue] {
        let value = call.argument(0)
        switch call.context.options.collectionArguments {
        case .whole: return value.map { [$0] } ?? []
        case .firstElement: return Array(AQLValues.coerceToCollection(value).prefix(1))
        }
    }

    private static func position(of value: (any EcoreValue)?, in items: [any EcoreValue], last: Bool) -> Int? {
        let indices = Array(items.indices)
        return (last ? indices.reversed() : indices).first { AQLValues.areEqual(items[$0], value) }
    }

    private static func flattened(_ items: [any EcoreValue]) -> [any EcoreValue] {
        items.flatMap { element -> [any EcoreValue] in
            AQLValues.elements(of: element).map(flattened) ?? [element]
        }
    }

    private static func numbers(_ items: [any EcoreValue], _ name: String) throws -> [any EcoreValue] {
        guard items.allSatisfy({ AQLValues.isNumber($0) }) else {
            throw AQLExecutionError.typeError("\(name) requires numeric elements")
        }
        return items
    }

    private static func extreme(_ call: AQLServiceCall, wantsMax: Bool) throws -> (any EcoreValue)? {
        let items = try numbers(call.receiverElements(), call.name)
        guard var best = items.first else { return nil }
        var allIntegers = AQLValues.integer(best) != nil
        for item in items.dropFirst() {
            allIntegers = allIntegers && AQLValues.integer(item) != nil
            if let order = AQLValues.compare(item, best),
                wantsMax ? order == .orderedDescending : order == .orderedAscending
            {
                best = item
            }
        }
        return allIntegers ? best : AQLValues.numericValue(best)
    }

    @MainActor
    private static func slice(_ call: AQLServiceCall) throws -> EcoreValueArray? {
        let items = call.receiverElements()
        let lower = try call.integer(0)
        let upper = try call.integer(1)
        guard lower >= 1, lower <= upper, upper <= items.count else { return nil }
        return result(Array(items[(lower - 1)..<upper]), of: call)
    }

    // MARK: - Services

    /// The services offered.
    public var services: [AQLService] {
        var list: [AQLService] = []
        func add(
            _ names: [String], arity: ClosedRange<Int> = 0...0, types: Bool = false,
            _ body: @escaping AQLServiceImplementation
        ) {
            for name in names {
                list.append(
                    AQLService(
                        name, receiver: .collection, arity: arity, acceptsTypeArguments: types,
                        implementation: body))
            }
        }

        // Queries
        add(["size"]) { $0.receiverElements().count }
        add(["isEmpty"]) { $0.receiverElements().isEmpty }
        add(["notEmpty"]) { !$0.receiverElements().isEmpty }
        add(["first"]) { $0.receiverElements().first }
        add(["last"]) { $0.receiverElements().last }
        add(["at"], arity: 1...1) { call in
            let items = call.receiverElements()
            let position = try call.integer(0)
            return position >= 1 && position <= items.count ? items[position - 1] : nil
        }
        for (name, last) in [("indexOf", false), ("lastIndexOf", true)] {
            add([name], arity: 1...1) { call in
                let items = call.receiverElements()
                if let lambda = call.argument(0) as? AQLLambda {
                    for (offset, element) in items.enumerated()
                    where Self.isTrue(try await lambda.invoke(element, in: call.context)) {
                        return call.context.usesOneBasedIndexOf ? offset + 1 : offset
                    }
                    return call.context.usesOneBasedIndexOf ? 0 : -1
                }
                let found = Self.position(of: call.argument(0), in: items, last: last)
                if call.context.usesOneBasedIndexOf { return (found ?? -1) + 1 }
                return found ?? -1
            }
        }
        add(["includes", "contains"], arity: 1...1) { Self.contains($0.receiverElements(), $0.argument(0)) }
        add(["excludes"], arity: 1...1) { !Self.contains($0.receiverElements(), $0.argument(0)) }
        add(["includesAll"], arity: 1...1) { call in
            let items = call.receiverElements()
            return call.elements(0).allSatisfy { Self.contains(items, $0) }
        }
        add(["excludesAll"], arity: 1...1) { call in
            let items = call.receiverElements()
            return !call.elements(0).contains { Self.contains(items, $0) }
        }
        add(["count"], arity: 1...1) { call in
            call.receiverElements().filter { AQLValues.areEqual($0, call.argument(0)) }.count
        }
        add(["sum"]) { call in
            let items = call.receiverElements()
            if !items.isEmpty, items.allSatisfy({ $0 is String }) {
                return items.compactMap { $0 as? String }.joined()
            }
            let values = try Self.numbers(items, call.name)
            if values.allSatisfy({ AQLValues.integer($0) != nil }) {
                return values.compactMap { AQLValues.integer($0) }.reduce(0, +)
            }
            return values.compactMap { AQLValues.numericValue($0) }.reduce(0, +)
        }
        add(["min"]) { try Self.extreme($0, wantsMax: false) }
        add(["max"]) { try Self.extreme($0, wantsMax: true) }

        // Iterators
        add(["select"], arity: 1...1) { try await Self.filter($0, keeping: true) }
        add(["reject"], arity: 1...1) { try await Self.filter($0, keeping: false) }
        add(["collect"], arity: 1...1) { call in
            var result: [any EcoreValue] = []
            for element in call.receiverElements() {
                guard let value = try await Self.evaluate(call, element) else { continue }
                result.append(contentsOf: AQLValues.elements(of: value) ?? [value])
            }
            return Self.result(result, of: call)
        }
        add(["any"], arity: 1...1) { call in
            for element in call.receiverElements() where Self.isTrue(try await Self.evaluate(call, element)) {
                return element
            }
            return nil
        }
        add(["exists"], arity: 1...1) { call in
            for element in call.receiverElements() where Self.isTrue(try await Self.evaluate(call, element)) {
                return true
            }
            return false
        }
        add(["forAll"], arity: 1...1) { call in
            for element in call.receiverElements() where !Self.isTrue(try await Self.evaluate(call, element)) {
                return false
            }
            return true
        }
        add(["one"], arity: 1...1) { call in
            var matches = 0
            for element in call.receiverElements() where Self.isTrue(try await Self.evaluate(call, element)) {
                matches += 1
            }
            return matches == 1
        }
        add(["isUnique"], arity: 1...1) { call in
            var keys: [any EcoreValue] = []
            for element in call.receiverElements() {
                let key = try await Self.evaluate(call, element)
                if let key {
                    if Self.contains(keys, key) { return false }
                    keys.append(key)
                }
            }
            return true
        }
        add(["sortedBy"], arity: 1...1) { call in
            let items = call.receiverElements()
            var keyed: [(key: (any EcoreValue)?, element: any EcoreValue)] = []
            for element in items { keyed.append((try await Self.evaluate(call, element), element)) }
            let ordered = keyed.enumerated().sorted { lhs, rhs in
                if let order = AQLValues.compare(lhs.element.key, rhs.element.key), order != .orderedSame {
                    return order == .orderedAscending
                }
                return lhs.offset < rhs.offset
            }
            return Self.result(ordered.map(\.element.element), of: call)
        }
        add(["closure"], arity: 1...1) { call in
            var result: [any EcoreValue] = []
            var pending = call.receiverElements()
            while !pending.isEmpty {
                let element = pending.removeFirst()
                guard let produced = try await Self.evaluate(call, element) else { continue }
                for next in AQLValues.coerceToCollection(produced) where !Self.contains(result, next) {
                    result.append(next)
                    pending.append(next)
                }
            }
            let kind = EcoreCollectionKind(ordered: call.receiverKind.isOrdered, unique: true)
            return call.context.collection(result, kind: kind)
        }
        add(["filter"], arity: 1...1, types: true) { call in
            let type = try call.type(0)
            return Self.result(call.receiverElements().filter(type.isKind), of: call)
        }

        // Transformations
        add(["including"], arity: 1...1) { call in
            Self.result(call.receiverElements() + Self.single(call), of: call)
        }
        add(["append"], arity: 1...1) { call in
            let added = Self.single(call)
            var items = call.receiverElements()
            if call.receiverKind.isUnique { items.removeAll { Self.contains(added, $0) } }
            return Self.result(items + added, of: call)
        }
        add(["prepend"], arity: 1...1) { call in
            Self.result(Self.single(call) + call.receiverElements(), of: call)
        }
        add(["excluding"], arity: 1...1) { call in
            Self.result(call.receiverElements().filter { !AQLValues.areEqual($0, call.argument(0)) }, of: call)
        }
        add(["union"], arity: 1...1) { call in
            Self.result(AQLValues.distinct(call.receiverElements() + call.elements(0)), of: call)
        }
        add(["concat", "addAll", "+"], arity: 1...1) { call in
            Self.result(call.receiverElements() + call.elements(0), of: call)
        }
        add(["intersection"], arity: 1...1) { call in
            let other = call.elements(0)
            return Self.result(call.receiverElements().filter { Self.contains(other, $0) }, of: call)
        }
        add(["sub", "difference", "removeAll"], arity: 1...1) { call in
            let other = call.elements(0)
            return Self.result(call.receiverElements().filter { !Self.contains(other, $0) }, of: call)
        }
        add(["insertAt"], arity: 2...2) { call in
            var items = call.receiverElements()
            let position = try call.integer(0)
            guard position >= 1, position <= items.count + 1, let value = call.argument(1) else { return nil }
            if call.receiverKind.isUnique { items.removeAll { AQLValues.areEqual($0, value) } }
            items.insert(value, at: Swift.min(position - 1, items.count))
            return Self.result(items, of: call)
        }
        add(["reverse"]) { Self.result($0.receiverElements().reversed(), of: $0) }
        add(["flatten"]) { Self.result(Self.flattened($0.receiverElements()), of: $0) }
        let conversions: [(String, EcoreCollectionKind)] = [
            ("asSequence", .sequence), ("asOrderedSet", .orderedSet), ("asSet", .set), ("asBag", .bag),
        ]
        for (name, kind) in conversions {
            add([name]) { $0.context.collection($0.receiverElements(), kind: kind) }
        }
        add(["drop"], arity: 1...1) { call in
            Self.result(Array(call.receiverElements().dropFirst(Swift.max(0, try call.integer(0)))), of: call)
        }
        add(["dropRight"], arity: 1...1) { call in
            Self.result(Array(call.receiverElements().dropLast(Swift.max(0, try call.integer(0)))), of: call)
        }
        add(["subSequence", "subOrderedSet"], arity: 2...2) { try Self.slice($0) }
        add(["sep"], arity: 1...1) { call in
            var result: [any EcoreValue] = []
            for (offset, element) in call.receiverElements().enumerated() {
                if offset > 0, let separator = call.argument(0) { result.append(separator) }
                result.append(element)
            }
            return EcoreValueArray(result)
        }
        add(["sep"], arity: 3...4) { call in
            let items = call.receiverElements()
            if items.isEmpty, call.arguments.count == 4, call.argument(3) as? Bool == false {
                return EcoreValueArray([])
            }
            var result: [any EcoreValue] = []
            if let prefix = call.argument(0) { result.append(prefix) }
            for (offset, element) in items.enumerated() {
                if offset > 0, let separator = call.argument(1) { result.append(separator) }
                result.append(element)
            }
            if let suffix = call.argument(2) { result.append(suffix) }
            return EcoreValueArray(result)
        }
        return list
    }
}
