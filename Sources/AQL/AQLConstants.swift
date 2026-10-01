//
//  AQLConstants.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Syntactic constants of AQL shared across the package.
public enum AQLSyntax {
    /// The separator between package and type names in qualified type names.
    public static let packageSeparator = "::"

    /// The textual form of null.
    public static let nullText = "null"

    /// The variable holding the current object.
    public static let selfVariable = "self"
}

/// Names of the primitive and built-in types recognised by type operations.
public enum AQLBuiltInType {
    /// The universal type.
    public static let any = "OclAny"
    /// Names denoting strings.
    public static let strings: Set<String> = ["String", "EString"]
    /// Names denoting integers.
    public static let integers: Set<String> = ["Integer", "Int", "EInt", "ELong", "EShort", "EByte"]
    /// Names denoting reals.
    public static let reals: Set<String> = ["Real", "Double", "Float", "EDouble", "EFloat"]
    /// Names denoting booleans.
    public static let booleans: Set<String> = ["Boolean", "Bool", "EBoolean"]
    /// Names denoting collections.
    public static let collections: Set<String> = [
        "Collection", "Sequence", "OrderedSet", "Set", "Bag",
    ]
}

/// The supertype structure of the Ecore metamodel, used when a native object's
/// classifier does not itself describe its supertypes.
public enum AQLEcoreMetaTypes {
    /// The root of every object type.
    public static let root = "EObject"

    /// Direct supertypes by metaclass name.
    public static let superTypes: [String: [String]] = [
        "EModelElement": [],
        "ENamedElement": ["EModelElement"],
        "EAnnotation": ["EModelElement"],
        "EClassifier": ["ENamedElement"],
        "EClass": ["EClassifier"],
        "EDataType": ["EClassifier"],
        "EEnum": ["EDataType"],
        "EEnumLiteral": ["ENamedElement"],
        "EPackage": ["ENamedElement"],
        "EFactory": ["EModelElement"],
        "ETypedElement": ["ENamedElement"],
        "EStructuralFeature": ["ETypedElement"],
        "EAttribute": ["EStructuralFeature"],
        "EReference": ["EStructuralFeature"],
        "EOperation": ["ETypedElement"],
        "EParameter": ["ETypedElement"],
    ]

    /// All supertype names (transitively) of a metaclass name.
    ///
    /// - Parameter name: The metaclass name.
    /// - Returns: The transitive supertype names, excluding the root.
    public static func allSuperTypes(of name: String) -> Set<String> {
        var result: Set<String> = []
        var pending = superTypes[name] ?? []
        while let next = pending.popLast() {
            if result.insert(next).inserted { pending.append(contentsOf: superTypes[next] ?? []) }
        }
        return result
    }
}
