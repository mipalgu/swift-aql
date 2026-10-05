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

    // MARK: - Keywords

    /// The keyword that starts a conditional expression.
    public static let ifKeyword = "if"

    /// The keyword that separates the condition from the first branch of a conditional.
    public static let thenKeyword = "then"

    /// The keyword that starts the second branch of a conditional.
    public static let elseKeyword = "else"

    /// The keyword that ends a conditional expression.
    public static let endifKeyword = "endif"

    /// The keyword that starts a let expression.
    public static let letKeyword = "let"

    /// The keyword that separates the bindings of a let expression from its body.
    public static let inKeyword = "in"

    /// The keyword for the null literal.
    public static let nullKeyword = nullText

    /// The word for the boolean true literal.
    public static let trueLiteral = "true"

    /// The word for the boolean false literal.
    public static let falseLiteral = "false"

    /// The keyword for the logical and operator.
    public static let andKeyword = "and"

    /// The keyword for the logical or operator.
    public static let orKeyword = "or"

    /// The keyword for the logical exclusive or operator.
    public static let xorKeyword = "xor"

    /// The keyword for the logical implication operator.
    public static let impliesKeyword = "implies"

    /// The keyword for the logical negation operator.
    public static let notKeyword = "not"

    /// The keyword for the integer remainder operator.
    public static let modKeyword = "mod"

    /// The keyword for the integer division operator.
    public static let divKeyword = "div"

    /// The words that AQL reserves for its own syntax.
    ///
    /// The boolean literal words `true` and `false` are not included: they tokenise as literals.
    public static let structuralKeywords: Set<String> = [
        ifKeyword, thenKeyword, elseKeyword, endifKeyword, letKeyword, inKeyword, nullKeyword,
        andKeyword, orKeyword, xorKeyword, impliesKeyword, notKeyword, modKeyword, divKeyword,
    ]

    /// The names of operations that the AQL syntax gives special treatment.
    ///
    /// These are the iterating collection operations with a dedicated expression node, the
    /// collection queries, and the OCL type operations.
    public static let operationKeywords: Set<String> = [
        "select", "reject", "collect", "forAll", "exists", "any",
        "size", "isEmpty", "notEmpty", "first", "last",
        "oclIsKindOf", "oclIsTypeOf", "oclAsType", "oclIsUndefined",
    ]

    /// Every word that the tokeniser reports as a keyword.
    ///
    /// Keywords may still be used as the names of properties, operations, and variables.
    public static let keywords: Set<String> = structuralKeywords.union(operationKeywords)

    /// The words after which an operand rather than an operator is expected.
    ///
    /// A minus sign after one of these words is a sign, not a subtraction.
    public static let operandExpectingKeywords: Set<String> = [
        andKeyword, orKeyword, notKeyword, xorKeyword, impliesKeyword, inKeyword, modKeyword,
        divKeyword, thenKeyword, elseKeyword, ifKeyword, letKeyword, "elseif",
    ]

    // MARK: - Operators

    /// The text of the navigation arrow that applies an operation to a collection.
    public static let arrow = "->"

    /// The text of the addition operator.
    public static let plus = "+"

    /// The text of the subtraction and negation operator.
    public static let minus = "-"

    /// The text of the multiplication operator.
    public static let times = "*"

    /// The text of the division operator.
    public static let slash = "/"

    /// The text of the equality operator.
    public static let equals = "="

    /// The text of the inequality operator.
    public static let notEquals = "<>"

    /// The text of the less-than operator.
    public static let lessThan = "<"

    /// The text of the greater-than operator.
    public static let greaterThan = ">"

    /// The text of the less-than-or-equal operator.
    public static let lessOrEqual = "<="

    /// The text of the greater-than-or-equal operator.
    public static let greaterOrEqual = ">="

    /// The text that starts a comment, which extends to the end of the line.
    public static let commentPrefix = "--"

    /// The character that delimits string literals.
    public static let stringDelimiter: Character = "'"

    // MARK: - Operations

    /// The names of the collection types that can precede a collection literal.
    public static let collectionTypeNames: Set<String> = AQLBuiltInType.collections

    /// The names of library functions that apply to no receiver even inside iterator bodies.
    public static let standaloneFunctionNames: Set<String> = [
        "min", "max", "abs", "toString",
    ]

    /// The names of the OCL type operations, which apply to `self` when written without a receiver.
    public static let typeOperationNames: Set<String> = [
        "oclIsKindOf", "oclIsTypeOf", "oclAsType", "oclIsUndefined",
    ]

    /// The names of the operations whose arguments are types.
    public static let typeArgumentOperationNames: Set<String> = typeOperationNames.union(["filter"])

    /// The names of the arrow operations whose arguments may omit the iterator variable.
    public static let iteratorOperationNames: Set<String> = ["sortedBy", "closure", "one", "isUnique"]
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
