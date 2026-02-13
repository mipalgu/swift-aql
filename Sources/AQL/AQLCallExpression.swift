//
//  AQLCallExpression.swift
//  AQL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Method Call Expression

/// Represents method/operation calls in AQL.
///
/// Call expressions invoke operations on objects or call standalone functions.
/// This includes OCL standard library operations, custom queries, and services.
///
/// ## Call Types
///
/// ### Object Operations
/// ```swift
/// // obj.toString()
/// AQLCallExpression(
///     source: objExpr,
///     methodName: "toString",
///     arguments: []
/// )
/// ```
///
/// ### Standalone Functions
/// ```swift
/// // max(value1, value2)
/// AQLCallExpression(
///     source: nil,
///     methodName: "max",
///     arguments: [value1Expr, value2Expr]
/// )
/// ```
///
/// ## Standard Library
///
/// AQL provides standard operations on primitives and collections following OCL semantics.
public struct AQLCallExpression: AQLExpression {

    // MARK: - Properties

    /// Optional source object expression (nil for standalone functions).
    public let source: (any AQLExpression)?

    /// The method/function name to invoke.
    public let methodName: String

    /// Argument expressions passed to the method.
    public let arguments: [any AQLExpression]

    // MARK: - Initialisation

    /// Creates a method call expression.
    ///
    /// - Parameters:
    ///   - source: Optional source object (nil for standalone functions)
    ///   - methodName: The method name
    ///   - arguments: The argument expressions
    public init(
        source: (any AQLExpression)? = nil,
        methodName: String,
        arguments: [any AQLExpression] = []
    ) {
        self.source = source
        self.methodName = methodName
        self.arguments = arguments
    }

    // MARK: - Evaluation

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        // Handle OCL type operations specially — type arg is a name, not a value
        if methodName == "oclIsKindOf" || methodName == "oclIsTypeOf" || methodName == "oclAsType" {
            return try await evaluateOCLTypeOperation(in: context)
        }

        // Evaluate source if present
        let sourceValue = try await source?.evaluate(in: context)

        // Evaluate arguments
        var argumentValues: [(any EcoreValue)?] = []
        for argExpr in arguments {
            let argValue = try await argExpr.evaluate(in: context)
            argumentValues.append(argValue)
        }

        // Try standard library operations first
        if let result = try? evaluateStandardLibrary(
            source: sourceValue, method: methodName, arguments: argumentValues)
        {
            return result
        }

        // If source is an EObject, try invoking operation through execution engine
        if sourceValue is (any EObject) {
            // TODO: Delegate to execution engine for EOperation invocation
            throw AQLExecutionError.invalidOperation(
                "EOperation invocation not yet implemented for '\(methodName)'")
        }

        throw AQLExecutionError.invalidOperation("Unknown method: \(methodName)")
    }

    // MARK: - OCL Type Operations

    /// Evaluates OCL type operations (oclIsKindOf, oclIsTypeOf, oclAsType).
    ///
    /// These operations require special handling because the type argument is a type name literal,
    /// not a runtime value. The type argument arrives as an `AQLVariableExpression` with the type name.
    private func evaluateOCLTypeOperation(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let sourceValue = try await source?.evaluate(in: context)

        // Extract type name from the first argument expression
        guard let firstArg = arguments.first,
              let varExpr = firstArg as? AQLVariableExpression else {
            throw AQLExecutionError.invalidOperation(
                "\(methodName) requires a type name argument")
        }
        let typeName = varExpr.name

        guard let eobj = sourceValue as? DynamicEObject else {
            // Non-EObject: fall back to Swift type name comparison
            if let sv = sourceValue {
                let swiftTypeName = String(describing: Swift.type(of: sv))
                switch methodName {
                case "oclIsTypeOf": return swiftTypeName == typeName
                case "oclIsKindOf": return swiftTypeName == typeName
                case "oclAsType": return sourceValue
                default: return false
                }
            }
            return false
        }

        switch methodName {
        case "oclIsTypeOf":
            return eobj.eClass.name == typeName
        case "oclIsKindOf":
            return eobj.eClass.name == typeName
                || eobj.eClass.allSuperTypes.contains { $0.name == typeName }
        case "oclAsType":
            // Dynamic objects: casting is a no-op, the object already has all features
            return sourceValue
        default:
            throw AQLExecutionError.invalidOperation("Unknown OCL type operation: \(methodName)")
        }
    }

    // MARK: - Standard Library

    /// Evaluates standard library operations.
    private func evaluateStandardLibrary(
        source: (any EcoreValue)?,
        method: String,
        arguments: [(any EcoreValue)?]
    ) throws -> (any EcoreValue)? {
        // String operations
        if let str = source as? String {
            return try evaluateStringOperation(str, method: method, arguments: arguments)
        }

        // Collection operations (some are also available as methods)
        if let collection = source as? [any EcoreValue] {
            return try evaluateCollectionOperation(
                collection, method: method, arguments: arguments)
        }

        // Standalone functions
        if source == nil {
            return try evaluateStandaloneFunction(method: method, arguments: arguments)
        }

        throw AQLExecutionError.invalidOperation("No standard library operation found")
    }

    // MARK: - String Operations

    private func evaluateStringOperation(
        _ str: String,
        method: String,
        arguments: [(any EcoreValue)?]
    ) throws -> (any EcoreValue)? {
        switch method {
        case "size", "length":
            return str.count

        case "toUpperCase", "upper":
            return str.uppercased()

        case "toLowerCase", "lower":
            return str.lowercased()

        case "substring":
            guard arguments.count >= 2,
                let start = arguments[0] as? Int,
                let end = arguments[1] as? Int
            else {
                throw AQLExecutionError.typeError("substring requires two integer arguments")
            }
            let startIndex = str.index(str.startIndex, offsetBy: start)
            let endIndex = str.index(str.startIndex, offsetBy: end)
            return String(str[startIndex..<endIndex])

        case "startsWith":
            guard let prefix = arguments.first as? String else {
                throw AQLExecutionError.typeError("startsWith requires string argument")
            }
            return str.hasPrefix(prefix)

        case "endsWith":
            guard let suffix = arguments.first as? String else {
                throw AQLExecutionError.typeError("endsWith requires string argument")
            }
            return str.hasSuffix(suffix)

        case "contains":
            guard let substring = arguments.first as? String else {
                throw AQLExecutionError.typeError("contains requires string argument")
            }
            return str.contains(substring)

        case "trim":
            return str.trimmingCharacters(in: .whitespaces)

        case "replace":
            guard arguments.count >= 2,
                let target = arguments[0] as? String,
                let replacement = arguments[1] as? String
            else {
                throw AQLExecutionError.typeError("replace requires two string arguments")
            }
            return str.replacingOccurrences(of: target, with: replacement)

        default:
            throw AQLExecutionError.invalidOperation("Unknown string operation: \(method)")
        }
    }

    // MARK: - Collection Operations

    private func evaluateCollectionOperation(
        _ collection: [any EcoreValue],
        method: String,
        arguments: [(any EcoreValue)?]
    ) throws -> (any EcoreValue)? {
        switch method {
        case "size":
            return collection.count

        case "isEmpty":
            return collection.isEmpty

        case "notEmpty":
            return !collection.isEmpty

        case "first":
            return collection.first

        case "last":
            return collection.last

        case "at":
            guard let index = arguments.first as? Int else {
                throw AQLExecutionError.typeError("at requires integer argument")
            }
            guard index >= 0 && index < collection.count else {
                return nil
            }
            return collection[index]

        case "indexOf":
            guard let element = arguments.first else {
                throw AQLExecutionError.typeError("indexOf requires an argument")
            }
            // Simple string-based comparison
            if let index = collection.firstIndex(where: {
                String(describing: $0) == String(describing: element)
            }) {
                return index
            }
            return -1

        case "includes", "contains":
            guard let element = arguments.first else {
                throw AQLExecutionError.typeError("includes requires an argument")
            }
            return collection.contains(where: {
                String(describing: $0) == String(describing: element)
            })

        default:
            throw AQLExecutionError.invalidOperation("Unknown collection operation: \(method)")
        }
    }

    // MARK: - Standalone Functions

    private func evaluateStandaloneFunction(
        method: String,
        arguments: [(any EcoreValue)?]
    ) throws -> (any EcoreValue)? {
        switch method {
        case "min":
            guard arguments.count == 2 else {
                throw AQLExecutionError.typeError("min requires exactly 2 arguments")
            }
            if let left = arguments[0] as? Int, let right = arguments[1] as? Int {
                return Swift.min(left, right)
            }
            if let left = arguments[0] as? Double, let right = arguments[1] as? Double {
                return Swift.min(left, right)
            }
            throw AQLExecutionError.typeError("min requires numeric arguments")

        case "max":
            guard arguments.count == 2 else {
                throw AQLExecutionError.typeError("max requires exactly 2 arguments")
            }
            if let left = arguments[0] as? Int, let right = arguments[1] as? Int {
                return Swift.max(left, right)
            }
            if let left = arguments[0] as? Double, let right = arguments[1] as? Double {
                return Swift.max(left, right)
            }
            throw AQLExecutionError.typeError("max requires numeric arguments")

        case "abs":
            guard let value = arguments.first else {
                throw AQLExecutionError.typeError("abs requires an argument")
            }
            if let intValue = value as? Int {
                return abs(intValue)
            }
            if let doubleValue = value as? Double {
                return abs(doubleValue)
            }
            throw AQLExecutionError.typeError("abs requires numeric argument")

        case "toString":
            guard let value = arguments.first else {
                return "null"
            }
            return String(describing: value)

        default:
            throw AQLExecutionError.invalidOperation("Unknown function: \(method)")
        }
    }
}
