//
//  AQLValues.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Value helpers shared by the standard library and by client-written services.
///
/// The helpers implement the AQL value model on top of ``EcoreValue``:
/// collections are `EcoreValueArray` (or any array of values), objects are
/// compared by identity, and numbers compare by value across integer and real
/// representations.
public enum AQLValues {

    // MARK: Collections

    /// The elements of a collection value.
    ///
    /// - Parameter value: The value to inspect.
    /// - Returns: The elements, or nil if the value is not a collection.
    public static func elements(of value: (any EcoreValue)?) -> [any EcoreValue]? {
        if let array = value as? EcoreValueArray { return array.values }
        if value is String { return nil }
        if let array = value as? [any EcoreValue] { return array }
        return nil
    }

    /// Coerces a value to a list of elements as `->` does.
    ///
    /// - Parameter value: The value to coerce.
    /// - Returns: The elements of a collection, an empty list for null, or a singleton.
    public static func coerceToCollection(_ value: (any EcoreValue)?) -> [any EcoreValue] {
        guard let value else { return [] }
        return elements(of: value) ?? [value]
    }

    /// Wraps elements as a collection value.
    ///
    /// - Parameter elements: The elements.
    /// - Returns: The collection value.
    public static func collection(_ elements: [any EcoreValue]) -> EcoreValueArray {
        EcoreValueArray(elements)
    }

    /// Removes duplicates (by ``areEqual(_:_:)``), keeping the first occurrence.
    ///
    /// - Parameter elements: The elements.
    /// - Returns: The distinct elements in their original order.
    public static func distinct(_ elements: [any EcoreValue]) -> [any EcoreValue] {
        var result: [any EcoreValue] = []
        var buckets: [AnyHashable: [Int]] = [:]
        var unkeyed: [Int] = []
        for element in elements {
            let key = hashKey(element)
            let candidates = key.map { buckets[$0] ?? [] } ?? unkeyed
            if candidates.contains(where: { areEqual(result[$0], element) }) { continue }
            if let key {
                buckets[key, default: []].append(result.count)
            } else {
                unkeyed.append(result.count)
            }
            result.append(element)
        }
        return result
    }

    private static func hashKey(_ value: any EcoreValue) -> AnyHashable? {
        if let object = value as? any EObject { return AnyHashable(object.id) }
        if let double = numericValue(value) { return AnyHashable(double) }
        if let string = value as? String { return AnyHashable(string) }
        if let bool = value as? Bool { return AnyHashable(bool) }
        return nil
    }

    // MARK: Equality

    /// Compares two values the way AQL's `=` does.
    ///
    /// Objects are equal when their identifiers match, numbers are equal when
    /// their numeric values match, collections are equal when their elements
    /// are pairwise equal, and other values are equal when they have the same
    /// type and compare equal.
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    /// - Returns: `true` if the values are equal.
    public static func areEqual(_ lhs: (any EcoreValue)?, _ rhs: (any EcoreValue)?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        let leftObject = lhs as? any EObject
        let rightObject = rhs as? any EObject
        if leftObject != nil || rightObject != nil {
            guard let leftObject, let rightObject else { return false }
            return leftObject.id == rightObject.id
        }
        if let left = elements(of: lhs), let right = elements(of: rhs) {
            return left.count == right.count && zip(left, right).allSatisfy { areEqual($0, $1) }
        }
        if let left = integer(lhs), let right = integer(rhs) { return left == right }
        if let left = numericValue(lhs), let right = numericValue(rhs) { return left == right }
        return sameTypeEqual(lhs, rhs)
    }

    private static func sameTypeEqual<T: EcoreValue>(_ lhs: T, _ rhs: any EcoreValue) -> Bool {
        guard let rhs = rhs as? T else { return false }
        return lhs == rhs
    }

    // MARK: Numbers

    /// Whether the value is an integer or real number.
    ///
    /// - Parameter value: The value to inspect.
    public static func isNumber(_ value: (any EcoreValue)?) -> Bool {
        numericValue(value) != nil
    }

    /// The value as an `Int`, if it is an integral number type.
    ///
    /// - Parameter value: The value to convert.
    /// - Returns: The integer, or nil for non-integers.
    public static func integer(_ value: (any EcoreValue)?) -> Int? {
        switch value {
        case let value as Int: return value
        case let value as Int64: return Int(value)
        case let value as Int16: return Int(value)
        case let value as Int8: return Int(value)
        default: return nil
        }
    }

    /// The value as a `Double`, if it is a numeric type.
    ///
    /// - Parameter value: The value to convert.
    /// - Returns: The real, or nil for non-numbers.
    public static func numericValue(_ value: (any EcoreValue)?) -> Double? {
        if let int = integer(value) { return Double(int) }
        switch value {
        case let value as Double: return value
        case let value as Float: return Double(value)
        default: return nil
        }
    }

    // MARK: Ordering

    /// Orders two values of the same comparable kind (numbers, strings, booleans).
    ///
    /// - Parameters:
    ///   - lhs: The left value.
    ///   - rhs: The right value.
    /// - Returns: The ordering, or nil if the values cannot be ordered.
    public static func compare(_ lhs: (any EcoreValue)?, _ rhs: (any EcoreValue)?) -> ComparisonResult? {
        if let left = integer(lhs), let right = integer(rhs) {
            return left < right ? .orderedAscending : (left == right ? .orderedSame : .orderedDescending)
        }
        if let left = numericValue(lhs), let right = numericValue(rhs) {
            return left < right ? .orderedAscending : (left == right ? .orderedSame : .orderedDescending)
        }
        if let left = lhs as? String, let right = rhs as? String {
            return left < right ? .orderedAscending : (left == right ? .orderedSame : .orderedDescending)
        }
        if let left = lhs as? Bool, let right = rhs as? Bool {
            return left == right ? .orderedSame : (!left ? .orderedAscending : .orderedDescending)
        }
        return nil
    }

    // MARK: Formatting

    /// Formats a value as text, as `toString()` does.
    ///
    /// Null is `null`, collections are `[a, b]`, objects are `ClassName@identifier`.
    ///
    /// - Parameter value: The value to format.
    /// - Returns: The textual form.
    public static func description(of value: (any EcoreValue)?) -> String {
        guard let value else { return AQLSyntax.nullText }
        if let string = value as? String { return string }
        if let items = elements(of: value) {
            return "[" + items.map { description(of: $0) }.joined(separator: ", ") + "]"
        }
        if let object = value as? any EObject {
            return "\(object.eClass.name)@\(object.id.uuidString)"
        }
        if let type = value as? AQLTypeDescriptor { return type.qualifiedName }
        return String(describing: value)
    }
}
