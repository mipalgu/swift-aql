//
//  AQLTypeDescriptor.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// A type usable as an argument of `filter`, `oclIsKindOf`, `eAllContents(Type)` and similar.
///
/// A descriptor names a classifier, optionally qualified by the name of its
/// package (`ecore::EClass`). Matching is by classifier name: the package
/// name is carried for documentation and for clients that need it but does not
/// restrict matching.
public struct AQLTypeDescriptor: EcoreValue {
    /// The package name, if the type was written qualified (nil otherwise).
    public let packageName: String?

    /// The classifier name.
    public let typeName: String

    /// Creates a type descriptor.
    ///
    /// - Parameters:
    ///   - packageName: The package name, or nil.
    ///   - typeName: The classifier name.
    public init(packageName: String? = nil, typeName: String) {
        self.packageName = packageName
        self.typeName = typeName
    }

    /// Creates a descriptor from a possibly qualified name such as `ecore::EClass`.
    ///
    /// - Parameter qualifiedName: The name, with `::` separating package segments.
    public init(qualifiedName: String) {
        let parts = qualifiedName.components(separatedBy: AQLSyntax.packageSeparator)
        self.typeName = parts.last ?? qualifiedName
        self.packageName = parts.count > 1
            ? parts.dropLast().joined(separator: AQLSyntax.packageSeparator) : nil
    }

    /// Creates a descriptor from a runtime value that denotes a type.
    ///
    /// - Parameter value: An ``AQLTypeDescriptor`` or an `EClass`.
    /// - Returns: The descriptor, or nil if the value does not denote a type.
    public init?(value: (any EcoreValue)?) {
        switch value {
        case let descriptor as AQLTypeDescriptor: self = descriptor
        case let eClass as EClass: self.init(typeName: eClass.name)
        case let eEnum as EEnum: self.init(typeName: eEnum.name)
        case let dataType as EDataType: self.init(typeName: dataType.name)
        default: return nil
        }
    }

    /// The name including the package qualifier, if any.
    public var qualifiedName: String {
        guard let packageName else { return typeName }
        return packageName + AQLSyntax.packageSeparator + typeName
    }

    // MARK: Matching

    /// The names of the type of a value and of all its supertypes.
    private static func typeNames(of value: any EcoreValue) -> (own: String, all: Set<String>) {
        if let object = value as? any EObject {
            let classifier = object.eClass
            var all: Set<String> = [classifier.name, AQLEcoreMetaTypes.root]
            if let eClass = classifier as? EClass {
                all.formUnion(eClass.allSuperTypes.map(\.name))
            } else {
                all.formUnion(AQLEcoreMetaTypes.allSuperTypes(of: classifier.name))
            }
            return (classifier.name, all)
        }
        return (String(describing: Swift.type(of: value)), [])
    }

    /// Checks whether a value conforms to this type (`oclIsKindOf`).
    ///
    /// - Parameter value: The value to test.
    /// - Returns: `true` if the value's type is this type or a subtype.
    public func isKind(_ value: (any EcoreValue)?) -> Bool {
        guard let value else { return false }
        if typeName == AQLBuiltInType.any { return true }
        if value is any EObject {
            return Self.typeNames(of: value).all.contains(typeName)
        }
        return matchesPrimitive(value)
    }

    /// Checks whether a value has exactly this type (`oclIsTypeOf`).
    ///
    /// - Parameter value: The value to test.
    /// - Returns: `true` if the value's type is this type.
    public func isType(_ value: (any EcoreValue)?) -> Bool {
        guard let value else { return false }
        if value is any EObject { return Self.typeNames(of: value).own == typeName }
        return matchesPrimitive(value)
    }

    private func matchesPrimitive(_ value: any EcoreValue) -> Bool {
        if typeName == AQLBuiltInType.any { return true }
        if AQLBuiltInType.strings.contains(typeName) { return value is String }
        if AQLBuiltInType.booleans.contains(typeName) { return value is Bool }
        if AQLBuiltInType.integers.contains(typeName) { return AQLValues.integer(value) != nil }
        if AQLBuiltInType.reals.contains(typeName) {
            return value is Double || value is Float
        }
        if AQLBuiltInType.collections.contains(typeName) { return AQLValues.elements(of: value) != nil }
        return Self.typeNames(of: value).own == typeName
    }
}
