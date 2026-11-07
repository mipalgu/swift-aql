//
//  OCLToAQLTranslator.swift
//  AQL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OCL

/// The outcome of translating an OCL expression into AQL.
public struct OCLToAQLTranslation: Sendable {
    /// The AQL text, or `nil` if the expression uses a construct that has no translation.
    public var aql: String?

    /// The constructs that have no translation (errors), whose translation differs from OCL in
    /// some cases (warnings), or that rely on services outside the AQL library (information).
    public var diagnostics: [SourceDiagnostic]

    /// Creates a translation.
    ///
    /// - Parameters:
    ///   - aql: The AQL text, if every construct was translated.
    ///   - diagnostics: The notes about the translation.
    public init(aql: String?, diagnostics: [SourceDiagnostic]) {
        self.aql = aql
        self.diagnostics = diagnostics
    }

    /// Whether every construct of the expression was translated.
    public var isComplete: Bool { aql != nil }
}

/// Translates the common subset of Essential OCL into AQL, so that an AQL evaluator can check
/// OCL invariants.
///
/// AQL shares most of its syntax with OCL; the translation rewrites the constructs whose
/// meaning differs:
///
/// - An implicit iterator in AQL rebinds `self` to the element, so an explicit `self` inside
///   such a body becomes a variable bound to the context object around the whole expression.
/// - A call without a source, such as `isAvailable()`, becomes a call on `self`.
/// - `/` divides integers in AQL, so its left operand is made real first.
/// - `->forAll` and `->exists` with several iterators become nested iterations.
/// - A two-segment enumeration literal such as `Genre::fiction` gains the name of its package,
///   which AQL requires, and so does the type of `allInstances()`.
/// - Unary minus applies to the whole navigation, as in OCL (`-x.abs()` is `-(x.abs())`).
/// - `oclType()` becomes `eClass()`, `selectByKind` becomes `filter`, `collectNested`
///   becomes `collect` and `?->` drops null elements before the call.
///
/// Constructs without an AQL counterpart (`iterate`, tuples, maps, ranges in collection
/// literals, `@pre`, `invalid`, messages, lambdas and `oclIsInvalid`) are reported as
/// `OCLDiagnosticCode.untranslatable` errors and leave the translation without text.
/// Translations whose meaning can differ, such as `collectNested`, `?.`, or a string's
/// `lastIndexOf`, carry a `OCLDiagnosticCode.semanticGap` warning.
public struct OCLToAQLTranslator: Sendable {
    /// The name of the variable that holds the context object where AQL rebinds `self`.
    public static let contextVariable = "oclSelf"

    /// The prefix of the variables that hold the source of a nested iteration.
    public static let sourceVariablePrefix = "oclSource"

    /// The OCL operations whose AQL counterpart has another name.
    public static let renamedOperations: [String: String] = [
        "oclType": "eClass", "toUpper": "toUpper", "toLower": "toLower",
        "lastIndexOf": "lastIndex", "collectNested": "collect", "selectByKind": "filter",
    ]

    /// The operations of the OCL standard library that AQL offers with the same meaning.
    public static let libraryOperations: Set<String> = [
        "abs", "floor", "round", "max", "min", "div", "mod", "toString", "size", "concat",
        "substring", "toUpperCase", "toLowerCase", "toUpper", "toLower", "at", "characters",
        "toInteger", "toReal", "toBoolean", "startsWith", "endsWith", "trim", "tokenize",
        "matches", "replaceAll", "equalsIgnoreCase", "indexOf", "lastIndexOf", "oclIsKindOf",
        "oclIsTypeOf", "oclAsType", "oclIsUndefined", "oclType", "allInstances", "isEmpty",
        "notEmpty", "first", "last", "includes", "excludes", "includesAll", "excludesAll",
        "including", "excluding", "union", "intersection", "count", "sum", "asSet", "asSequence",
        "asOrderedSet", "asBag", "flatten", "reverse", "append", "prepend", "insertAt",
        "subSequence", "subOrderedSet", "select", "reject", "collect", "collectNested", "forAll",
        "exists", "any", "one", "isUnique", "sortedBy", "closure", "selectByKind", "selectByType",
    ]

    /// The OCL constructs that have no AQL counterpart, by operation name.
    public static let untranslatableOperations: Set<String> = [
        "iterate", "oclIsInvalid", "oclIsNew", "oclInState", "product", "symmetricDifference",
        "collectBy", "oclAsSet",
    ]

    /// The iterations that AQL evaluates with an implicit iterator when none is declared.
    public static let implicitIterations: Set<String> = [
        "select", "reject", "collect", "any", "exists", "forAll", "sortedBy", "closure", "one",
        "isUnique", "collectNested",
    ]

    /// The iterations that may declare several iterators, which are translated as nested iterations.
    public static let nestableIterations: Set<String> = ["forAll", "exists"]

    /// The packages whose enumerations and classes qualify names.
    public var packages: [EPackage]

    /// Creates a translator.
    ///
    /// - Parameter packages: The packages whose enumerations and classes qualify names such as
    ///   `Genre::fiction` and `Book.allInstances()`.
    public init(packages: [EPackage] = []) {
        self.packages = packages
    }

    /// Parses and translates OCL text.
    ///
    /// - Parameter source: The OCL expression.
    /// - Returns: The translation, or the syntax errors of the text.
    public func translate(_ source: String) -> OCLToAQLTranslation {
        let parsed = OCLExpressionParser().parse(source)
        guard let expression = parsed.expression else {
            return OCLToAQLTranslation(aql: nil, diagnostics: parsed.diagnostics)
        }
        return translate(expression)
    }

    /// Translates a parsed OCL expression.
    ///
    /// - Parameter expression: The OCL expression.
    /// - Returns: The translation.
    public func translate(_ expression: OCLExpression) -> OCLToAQLTranslation {
        var state = State(translator: self)
        let text = state.emit(expression)
        var aql: String? = text
        if state.diagnostics.contains(where: { $0.severity == .error }) {
            aql = nil
        } else if state.usesContextVariable {
            aql = "let \(Self.contextVariable) = \(OCLSyntax.selfKeyword) in " + text
        }
        return OCLToAQLTranslation(aql: aql, diagnostics: state.diagnostics)
    }

    // MARK: - Name resolution

    /// The package path and enumeration that hold a literal, if any.
    func enumeration(named name: String, literal: String) -> [String]? {
        for (path, classifier) in classifiers() where classifier.name == name {
            if let eEnum = classifier as? EEnum, eEnum.getLiteral(name: literal) != nil { return path }
        }
        return nil
    }

    /// The package path of a classifier, if any.
    func packagePath(ofClassifier name: String) -> [String]? {
        classifiers().first { $0.1.name == name }?.0
    }

    /// Every classifier of the packages with the path of its package.
    func classifiers() -> [([String], any EClassifier)] {
        var result: [([String], any EClassifier)] = []
        /// Adds a package, its classifiers and its subpackages to the result.
        ///
        /// - Parameters:
        ///   - package: The package to visit.
        ///   - path: The names of the enclosing packages.
        func visit(_ package: EPackage, path: [String]) {
            let packagePath = path + [package.name]
            for classifier in package.eClassifiers { result.append((packagePath, classifier)) }
            for subpackage in package.eSubpackages { visit(subpackage, path: packagePath) }
        }
        for package in packages { visit(package, path: []) }
        return result
    }

    /// Whether a name is the name of a package.
    func isPackage(_ name: String) -> Bool {
        /// Whether a package or any of its subpackages has the name.
        ///
        /// - Parameter package: The package to search.
        /// - Returns: `true` if the name is found.
        func contains(_ package: EPackage) -> Bool {
            package.name == name || package.eSubpackages.contains(where: contains)
        }
        return packages.contains(where: contains)
    }

    // MARK: - Emission

    /// The state of one translation.
    private struct State {
        /// The translator that supplies the packages and settings.
        let translator: OCLToAQLTranslator
        /// The diagnostics collected so far.
        var diagnostics: [SourceDiagnostic] = []
        /// The nesting depth of implicit iterator scopes.
        var implicitDepth = 0
        /// Whether the translated expression refers to the context variable.
        var usesContextVariable = false
        /// The number of source variables generated so far, used to keep their names distinct.
        var sourceCounter = 0

        /// Creates an emitter.
        ///
        /// - Parameter translator: The translator that supplies the packages and settings.
        init(translator: OCLToAQLTranslator) {
            self.translator = translator
        }

        /// Reports an element that has no AQL translation.
        ///
        /// - Parameters:
        ///   - what: A description of the element.
        ///   - range: The source range of the element.
        /// - Returns: The text `null`, which stands in for the element.
        mutating func untranslatable(_ what: String, at range: SourceRange) -> String {
            diagnostics.append(
                SourceDiagnostic(
                    severity: .error, code: OCLDiagnosticCode.untranslatable,
                    message: "\(what) has no AQL translation", range: range))
            return "null"
        }

        /// Reports a difference between OCL and AQL semantics.
        ///
        /// - Parameters:
        ///   - message: The description of the difference.
        ///   - range: The source range of the expression.
        ///   - severity: The severity of the diagnostic.
        mutating func gap(_ message: String, at range: SourceRange, severity: DiagnosticSeverity = .warning) {
            diagnostics.append(
                SourceDiagnostic(severity: severity, code: OCLDiagnosticCode.semanticGap, message: message, range: range))
        }

        /// Translates an expression into text that can stand as an operand.
        mutating func operand(_ expression: OCLExpression) -> String {
            let text = emit(expression)
            switch expression.kind {
            case .integerLiteral, .realLiteral, .stringLiteral, .booleanLiteral, .nullLiteral, .selfReference,
                .name, .parenthesised, .collectionLiteral, .typeLiteral, .call:
                return text
            default:
                return "(" + text + ")"
            }
        }

        /// Translates an expression into AQL.
        ///
        /// - Parameter expression: The OCL expression.
        /// - Returns: The AQL text.
        mutating func emit(_ expression: OCLExpression) -> String {
            let range = expression.range
            switch expression.kind {
            case .integerLiteral(let digits):
                return digits
            case .realLiteral(let text):
                guard text.contains(where: { $0 == "e" || $0 == "E" }), let value = Double(text) else { return text }
                return String(value)
            case .stringLiteral(let value, let source):
                return OCLLexer.tokenise(source).significantTokens.count == 2 ? source : Self.quoted(value)
            case .booleanLiteral(let value):
                return value ? OCLSyntax.trueLiteral : OCLSyntax.falseLiteral
            case .nullLiteral:
                return OCLSyntax.nullLiteral
            case .invalidLiteral:
                return untranslatable("'invalid'", at: range)
            case .unlimitedLiteral:
                return untranslatable("The unlimited natural '*'", at: range)
            case .selfReference:
                guard implicitDepth > 0 else { return OCLSyntax.selfKeyword }
                usesContextVariable = true
                return OCLToAQLTranslator.contextVariable
            case .name(let segments, let isPre):
                if isPre { return untranslatable("'@pre'", at: range) }
                return name(segments, at: range)
            case .call(let call):
                return emit(call, at: range)
            case .prefix(let op, let operand):
                switch op {
                case OCLSyntax.notKeyword: return "not " + self.operand(operand)
                case "-":
                    switch operand.kind {
                    case .name, .selfReference, .parenthesised: return "-" + self.operand(operand)
                    default: return "-(" + emit(operand) + ")"
                    }
                default: return untranslatable("The operator '\(op)'", at: range)
                }
            case .infix(let op, let left, let right):
                return infix(op, left, right, at: range)
            case .conditional(let branches, let otherwise):
                var text = emit(otherwise)
                for branch in branches.reversed() {
                    text = "if \(emit(branch.condition)) then \(emit(branch.value)) else \(text) endif"
                }
                return text
            case .letExpression(let variables, let body):
                var bindings: [String] = []
                for variable in variables {
                    let value = variable.initialiser.map { emit($0) } ?? OCLSyntax.nullLiteral
                    bindings.append("let \(variable.name) = \(value) in ")
                }
                return bindings.joined() + emit(body)
            case .collectionLiteral(let type, let parts):
                var kind = type.name
                if kind == "Collection" {
                    gap("'Collection' literals become sequences in AQL", at: range)
                    kind = "Sequence"
                }
                var elements: [String] = []
                for part in parts {
                    switch part {
                    case .element(let element): elements.append(emit(element))
                    case .range: return untranslatable("A range in a collection literal", at: range)
                    }
                }
                return kind + "{" + elements.joined(separator: ", ") + "}"
            case .tupleLiteral:
                return untranslatable("A tuple literal", at: range)
            case .mapLiteral:
                return untranslatable("A map literal", at: range)
            case .typeLiteral(let type):
                return typeText(type)
            case .parenthesised(let inner):
                return "(" + emit(inner) + ")"
            case .indexed:
                return untranslatable("A square-bracketed qualifier", at: range)
            case .shadow:
                return untranslatable("A curly-bracketed object construction", at: range)
            case .lambda:
                return untranslatable("A lambda literal", at: range)
            case .message:
                return untranslatable("A message expression", at: range)
            case .unspecifiedValue:
                return untranslatable("The unspecified value '?'", at: range)
            }
        }

        /// Writes a string value as an AQL string literal.
        static func quoted(_ value: String) -> String {
            var result = "'"
            for character in value {
                switch character {
                case "'": result += "\\'"
                case "\\": result += "\\\\"
                case "\n": result += "\\n"
                case "\r": result += "\\r"
                case "\t": result += "\\t"
                default: result.append(character)
                }
            }
            return result + "'"
        }

        /// The AQL text of a type reference.
        ///
        /// - Parameter type: The type reference.
        /// - Returns: The qualified type name, with any type arguments in parentheses.
        func typeText(_ type: OCLTypeReference) -> String {
            var result = type.path.joined(separator: OCLSyntax.pathSeparator)
            if !type.arguments.isEmpty { result += "(" + type.arguments.map(typeText).joined(separator: ", ") + ")" }
            return result
        }

        /// Translates a qualified name, expanding enumeration literals to their package path.
        ///
        /// - Parameters:
        ///   - segments: The segments of the name.
        ///   - range: The source range of the name.
        /// - Returns: The AQL text.
        mutating func name(_ segments: [String], at range: SourceRange) -> String {
            let joined = segments.joined(separator: OCLSyntax.pathSeparator)
            guard segments.count == 2, !translator.packages.isEmpty, !translator.isPackage(segments[0]) else { return joined }
            if let path = translator.enumeration(named: segments[0], literal: segments[1]) {
                return (path + segments).joined(separator: OCLSyntax.pathSeparator)
            }
            gap("'\(joined)' is read by AQL as a type; name its package if it is an enumeration literal", at: range)
            return joined
        }

        /// Translates an infix operation.
        ///
        /// - Parameters:
        ///   - op: The operator.
        ///   - left: The left operand.
        ///   - right: The right operand.
        ///   - range: The source range of the operation.
        /// - Returns: The AQL text.
        mutating func infix(_ op: String, _ left: OCLExpression, _ right: OCLExpression, at range: SourceRange) -> String {
            switch op {
            case "and2", "or2", "xor2", "implies2":
                return untranslatable("The operator '\(op)'", at: range)
            case "/":
                return "\(operand(left)) * 1.0 / \(operand(right))"
            default:
                return "\(operand(left)) \(op) \(operand(right))"
            }
        }

        // MARK: Calls

        /// Translates a call.
        ///
        /// - Parameters:
        ///   - call: The call.
        ///   - range: The source range of the call.
        /// - Returns: The AQL text.
        mutating func emit(_ call: OCLCall, at range: SourceRange) -> String {
            if call.isPre { return untranslatable("'@pre'", at: range) }
            if !call.qualifier.isEmpty {
                return untranslatable("The qualified operation '\(call.qualifier.joined(separator: "::"))::\(call.name)'", at: range)
            }
            if OCLToAQLTranslator.untranslatableOperations.contains(call.name), call.arguments != nil {
                return untranslatable("The operation '\(call.name)'", at: range)
            }
            guard let source = call.source, let navigation = call.navigation else {
                guard let arguments = call.arguments else { return call.name }
                note(call, at: range)
                return OCLSyntax.selfKeyword + "." + operation(call.name, arguments, at: range)
            }
            let isCollection = OCLSyntax.collectionNavigationOperators.contains(navigation)
            var receiver: String
            if call.name == "allInstances", case .name(let segments, false) = source.kind, segments.count == 1 {
                if let path = translator.packagePath(ofClassifier: segments[0]) {
                    receiver = (path + segments).joined(separator: OCLSyntax.pathSeparator)
                } else {
                    gap("AQL needs the package of '\(segments[0])' to find its instances", at: source.range)
                    receiver = segments[0]
                }
            } else {
                receiver = operand(source)
            }
            if navigation == "?." {
                gap("'?.' becomes '.', which AQL evaluates to null for a null source", at: range, severity: .information)
            }
            if navigation == "?->" { receiver += "->excluding(null)" }
            guard let arguments = call.arguments else {
                return receiver + (isCollection ? "->" : ".") + call.name
            }
            note(call, at: range)
            if isCollection {
                return iteration(receiver, call.name, arguments, at: range)
            }
            return receiver + "." + operation(call.name, arguments, at: range)
        }

        /// Adds the notes that a call of an operation needs.
        mutating func note(_ call: OCLCall, at range: SourceRange) {
            let isString = call.navigation == nil || OCLSyntax.objectNavigationOperators.contains(call.navigation ?? "")
            switch call.name {
            case "collectNested":
                gap("'collectNested' becomes 'collect', which flattens nested collections", at: range)
            case "lastIndexOf" where isString:
                gap("A string's 'lastIndexOf' becomes 'lastIndex', which gives -1 rather than 0 for a missing substring", at: range)
            case "indexOf" where isString && call.navigation != "->":
                gap("A string's 'indexOf' needs the OCL string services of the invariant checker", at: range, severity: .information)
            case _ where !OCLToAQLTranslator.libraryOperations.contains(call.name):
                gap("'\(call.name)' is not in the AQL library and must be offered as a service", at: range, severity: .information)
            default:
                break
            }
        }

        /// Writes `name(arguments)` for an operation called with `.`.
        mutating func operation(_ name: String, _ arguments: OCLArguments, at range: SourceRange) -> String {
            if arguments.hasBody { return untranslatable("An iterator declaration after '.'", at: range) }
            let aqlName = OCLToAQLTranslator.renamedOperations[name] ?? name
            return aqlName + "(" + arguments.arguments.map { emit($0) }.joined(separator: ", ") + ")"
        }

        /// Writes `receiver->name(arguments)` for a collection operation or iteration.
        mutating func iteration(_ receiver: String, _ name: String, _ arguments: OCLArguments, at range: SourceRange) -> String {
            if !arguments.accumulators.isEmpty { return untranslatable("An accumulator", at: range) }
            if name == "selectByType", arguments.arguments.count == 1, !arguments.hasBody {
                let type = emit(arguments.arguments[0])
                return receiver + "->select(e | e.oclIsTypeOf(" + type + "))"
            }
            let aqlName = OCLToAQLTranslator.renamedOperations[name] ?? name
            guard OCLSyntax.iterationNames.contains(name), name != "selectByKind" else {
                if arguments.hasBody { return untranslatable("Iterators of '\(name)'", at: range) }
                return receiver + "->" + aqlName + "(" + arguments.arguments.map { emit($0) }.joined(separator: ", ") + ")"
            }
            guard arguments.arguments.count == 1, let body = arguments.arguments.first else {
                return untranslatable("The iteration '\(name)' without one body", at: range)
            }
            switch arguments.iterators.count {
            case 0:
                guard OCLToAQLTranslator.implicitIterations.contains(name) else {
                    return untranslatable("The iteration '\(name)' without an iterator", at: range)
                }
                implicitDepth += 1
                defer { implicitDepth -= 1 }
                return receiver + "->" + aqlName + "(" + emit(body) + ")"
            case 1:
                return receiver + "->" + aqlName + "(" + arguments.iterators[0].name + " | " + emit(body) + ")"
            default:
                guard OCLToAQLTranslator.nestableIterations.contains(name) else {
                    return untranslatable("Several iterators of '\(name)'", at: range)
                }
                sourceCounter += 1
                let source = OCLToAQLTranslator.sourceVariablePrefix + String(sourceCounter)
                var text = emit(body)
                for iterator in arguments.iterators.reversed() {
                    text = source + "->" + aqlName + "(" + iterator.name + " | " + text + ")"
                }
                return "(let " + source + " = " + receiver + " in " + text + ")"
            }
        }
    }
}
