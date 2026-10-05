//
//  AQLGrammar.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// The recursive descent grammar of AQL expressions.
///
/// From loosest to tightest binding the levels are `implies` (right associative), `or` and
/// `xor`, `and`, comparison, additive, multiplicative, unary `not` and `-`, and finally
/// navigation (`.`, `->`, calls) over primary expressions.
struct AQLGrammar<Delegate: AQLParserDelegate> {

    /// The tokens, the position in them, and the context of the expression.
    var cursor: AQLTokenCursor

    /// The host hooks.
    var delegate: Delegate

    // MARK: - Errors and helpers

    /// Builds the error for a problem at the current token.
    ///
    /// - Parameters:
    ///   - message: What is wrong.
    ///   - code: The diagnostic code (default: unexpected token).
    func error(_ message: String, code: String = AQLDiagnosticCode.unexpectedToken) -> AQLSyntaxError {
        let atEnd = cursor.currentKind == .eof
        return AQLSyntaxError(
            AQLDiagnostic(
                code: atEnd ? AQLDiagnosticCode.unexpectedEnd : code, message: message,
                span: cursor.errorSpan))
    }

    /// Consumes a token of the given kind.
    mutating func expect(_ kind: AQLTokenKind) throws {
        guard cursor.currentKind == kind else {
            throw error("Expected \(kind) but found \(cursor.currentKind)")
        }
        cursor.advance()
    }

    /// Consumes the given keyword.
    mutating func expectKeyword(_ keyword: String) throws {
        guard case .keyword(keyword) = cursor.currentKind else {
            throw error("Expected keyword '\(keyword)' but found \(cursor.currentKind)")
        }
        cursor.advance()
    }

    // MARK: - Names and types

    /// Parses one identifier, accepting keywords as names.
    ///
    /// - Parameter description: What the name denotes, for error messages.
    mutating func parseNameSegment(describing description: String) throws -> String {
        switch cursor.currentKind {
        case .identifier(let name), .keyword(let name):
            cursor.advance()
            return name
        default:
            throw error("Expected \(description)")
        }
    }

    /// Parses a name made of segments separated by `::`.
    ///
    /// - Parameter description: What the name denotes, for error messages.
    mutating func parseQualifiedName(describing description: String) throws -> String {
        var segments = [try parseNameSegment(describing: description)]
        while cursor.currentKind == .doubleColon {
            cursor.advance()
            segments.append(try parseNameSegment(describing: description))
        }
        return segments.joined(separator: AQLSyntax.packageSeparator)
    }

    /// Parses a type name such as `String`, `ecore::EClass`, or `Sequence(EClass)`.
    mutating func parseTypeName() throws -> String {
        var name = try parseQualifiedName(describing: "type name")
        if cursor.currentKind == .leftParen {
            cursor.advance()
            var arguments = [try parseTypeName()]
            while cursor.currentKind == .comma {
                cursor.advance()
                arguments.append(try parseTypeName())
            }
            try expect(.rightParen)
            name += "(" + arguments.joined(separator: ", ") + ")"
        }
        return name
    }

    // MARK: - Operators

    /// Parses an expression.
    mutating func parseExpression() throws -> any AQLExpression {
        try parseImplies()
    }

    /// Parses `implies`, the loosest binding operator, which associates to the right.
    private mutating func parseImplies() throws -> any AQLExpression {
        let left = try parseLogicalOr()
        guard case .keyword(AQLSyntax.impliesKeyword) = cursor.currentKind else { return left }
        cursor.advance()
        let right = try parseImplies()
        return AQLBinaryExpression(left: left, op: .implies, right: right)
    }

    private mutating func parseLogicalOr() throws -> any AQLExpression {
        var left = try parseLogicalAnd()
        while true {
            let op: AQLBinaryExpression.Operator
            switch cursor.currentKind {
            case .keyword(AQLSyntax.orKeyword): op = .or
            case .keyword(AQLSyntax.xorKeyword): op = .xor
            default: return left
            }
            cursor.advance()
            left = AQLBinaryExpression(left: left, op: op, right: try parseLogicalAnd())
        }
    }

    private mutating func parseLogicalAnd() throws -> any AQLExpression {
        var left = try parseComparison()
        while case .keyword(AQLSyntax.andKeyword) = cursor.currentKind {
            cursor.advance()
            left = AQLBinaryExpression(left: left, op: .and, right: try parseComparison())
        }
        return left
    }

    private mutating func parseComparison() throws -> any AQLExpression {
        var left = try parseAdditive()
        while let op = comparisonOperator() {
            cursor.advance()
            left = AQLBinaryExpression(left: left, op: op, right: try parseAdditive())
        }
        return left
    }

    /// The comparison operator at the current token, if any.
    private func comparisonOperator() -> AQLBinaryExpression.Operator? {
        guard case .operator(let text) = cursor.currentKind else { return nil }
        switch text {
        case AQLSyntax.equals: return .equals
        case AQLSyntax.notEquals: return .notEquals
        case AQLSyntax.lessThan: return .lessThan
        case AQLSyntax.greaterThan: return .greaterThan
        case AQLSyntax.lessOrEqual: return .lessOrEqual
        case AQLSyntax.greaterOrEqual: return .greaterOrEqual
        default: return nil
        }
    }

    private mutating func parseAdditive() throws -> any AQLExpression {
        var left = try parseMultiplicative()
        while true {
            let op: AQLBinaryExpression.Operator
            switch cursor.currentKind {
            case .operator(AQLSyntax.plus): op = .add
            case .operator(AQLSyntax.minus): op = .subtract
            default: return left
            }
            cursor.advance()
            left = AQLBinaryExpression(left: left, op: op, right: try parseMultiplicative())
        }
    }

    private mutating func parseMultiplicative() throws -> any AQLExpression {
        var left = try parseUnary()
        while true {
            let op: AQLBinaryExpression.Operator
            switch cursor.currentKind {
            case .operator(AQLSyntax.times): op = .multiply
            case .slash where !cursor.atTerminator: op = .divide
            case .keyword(AQLSyntax.modKeyword): op = .mod
            case .keyword(AQLSyntax.divKeyword): op = .div
            default: return left
            }
            cursor.advance()
            left = AQLBinaryExpression(left: left, op: op, right: try parseUnary())
        }
    }

    /// Parses unary `not` and `-`, which associate to the right.
    private mutating func parseUnary() throws -> any AQLExpression {
        switch cursor.currentKind {
        case .keyword(AQLSyntax.notKeyword):
            cursor.advance()
            return AQLUnaryExpression(op: .not, operand: try parseUnary())
        case .operator(AQLSyntax.minus):
            cursor.advance()
            return AQLUnaryExpression(op: .negate, operand: try parseUnary())
        default:
            return try parseNavigation()
        }
    }

    // MARK: - Navigation

    /// Parses `object.property`, `object.operation(arguments)`, and `collection->operation(...)`.
    private mutating func parseNavigation() throws -> any AQLExpression {
        var expression = try parsePrimary()
        while true {
            switch cursor.currentKind {
            case .dot:
                cursor.advance()
                let name: String
                switch cursor.currentKind {
                case .identifier(let text), .keyword(let text): name = text
                default: throw error("Expected property name after '.'")
                }
                cursor.advance()
                if cursor.currentKind == .leftParen {
                    let arguments = try parseCallArguments(forOperation: name)
                    expression = delegate.makeCall(name: name, receiver: expression, arguments: arguments)
                } else {
                    expression = AQLNavigationExpression(source: expression, property: name)
                }
            case .operator(AQLSyntax.arrow):
                cursor.advance()
                expression = try parseCollectionOperation(source: expression)
            default:
                return expression
            }
        }
    }

    /// Parses the operation after `->`.
    private mutating func parseCollectionOperation(source: any AQLExpression) throws -> any AQLExpression {
        let name: String
        switch cursor.currentKind {
        case .identifier(let text), .keyword(let text): name = text
        default: throw error("Expected collection operation name after '->'")
        }
        cursor.advance()

        let operation: AQLCollectionExpression.Operation
        switch name {
        case "select": operation = .select
        case "reject": operation = .reject
        case "collect": operation = .collect
        case "any": operation = .any
        case "exists": operation = .exists
        case "forAll": operation = .forAll
        case "size": operation = .size
        case "isEmpty": operation = .isEmpty
        case "notEmpty": operation = .notEmpty
        case "first": operation = .first
        case "last": operation = .last
        case "indexOf": operation = .indexOf
        default:
            return try parseGenericCollectionOperation(named: name, source: source)
        }

        switch operation {
        case .size, .isEmpty, .notEmpty, .first, .last:
            if cursor.currentKind == .leftParen {
                cursor.advance()
                try expect(.rightParen)
            }
            return AQLCollectionExpression(source: source, operation: operation)
        case .indexOf:
            try expect(.leftParen)
            let argument = try parseExpression()
            try expect(.rightParen)
            return AQLCollectionExpression(source: source, operation: operation, body: argument)
        default:
            break
        }

        try expect(.leftParen)
        let header = try parseLambdaHeader()
        let iterator = header?.name ?? AQLSyntax.selfVariable
        let usesImplicitIterator = header == nil
        if usesImplicitIterator { cursor.implicitReceiverDepth += 1 }
        defer { if usesImplicitIterator { cursor.implicitReceiverDepth -= 1 } }
        let body = try parseExpression()
        try expect(.rightParen)
        return AQLCollectionExpression(source: source, operation: operation, iterator: iterator, body: body)
    }

    /// Parses the arguments of a `->name(...)` operation that has no dedicated AQL node.
    private mutating func parseGenericCollectionOperation(
        named name: String, source: any AQLExpression
    ) throws -> any AQLExpression {
        var arguments: [any AQLExpression] = []
        if cursor.currentKind == .leftParen {
            arguments = try parseCallArguments(forOperation: name, afterArrow: true)
        }
        return AQLCallExpression(source: source, methodName: name, arguments: arguments, usesArrow: true)
    }

    // MARK: - Primary expressions

    private mutating func parsePrimary() throws -> any AQLExpression {
        switch cursor.currentKind {
        case .stringLiteral(let value):
            cursor.advance()
            return AQLLiteralExpression(value: value)
        case .integerLiteral(let value):
            cursor.advance()
            return AQLLiteralExpression(value: value)
        case .realLiteral(let value):
            cursor.advance()
            return AQLLiteralExpression(value: value)
        case .booleanLiteral(let value):
            cursor.advance()
            return AQLLiteralExpression(value: value)
        case .keyword(AQLSyntax.nullKeyword):
            cursor.advance()
            return AQLLiteralExpression(value: nil)
        case .keyword(AQLSyntax.ifKeyword):
            cursor.advance()
            return try parseConditional()
        case .keyword(AQLSyntax.letKeyword):
            cursor.advance()
            return try parseLet()
        case .identifier(let name), .keyword(let name):
            return try parseName(name)
        case .leftParen:
            cursor.advance()
            let expression = try parseExpression()
            try expect(.rightParen)
            return expression
        default:
            throw error("Expected expression but found \(cursor.currentKind)")
        }
    }

    /// Parses the rest of `if condition then a else b endif`; `if` is already consumed.
    private mutating func parseConditional() throws -> any AQLExpression {
        let condition = try parseExpression()
        try expectKeyword(AQLSyntax.thenKeyword)
        let thenExpression = try parseExpression()
        try expectKeyword(AQLSyntax.elseKeyword)
        let elseExpression = try parseExpression()
        try expectKeyword(AQLSyntax.endifKeyword)
        return AQLConditionalExpression(
            condition: condition, thenExpression: thenExpression, elseExpression: elseExpression)
    }

    /// Parses the rest of `let x : T = e, y = f in body`; `let` is already consumed.
    private mutating func parseLet() throws -> any AQLExpression {
        var bindings: [(String, any AQLExpression)] = []
        while true {
            let name = try parseNameSegment(describing: "variable name")
            if cursor.currentKind == .colon {
                cursor.advance()
                _ = try parseTypeName()
            }
            try expect(.operator(AQLSyntax.equals))
            bindings.append((name, try parseExpression()))
            guard cursor.currentKind == .comma else { break }
            cursor.advance()
        }
        try expectKeyword(AQLSyntax.inKeyword)
        return AQLLetExpression(bindings: bindings, body: try parseExpression())
    }

    /// Parses a name, a qualified name, a call, or a collection literal.
    ///
    /// The current token must be the identifier or keyword `first`.
    private mutating func parseName(_ first: String) throws -> any AQLExpression {
        if AQLSyntax.collectionTypeNames.contains(first), cursor.peekKind() == .leftBrace {
            return try parseCollectionLiteral(kind: first)
        }

        if let hosted = try delegate.parsePrimary(named: first, cursor: &cursor) { return hosted }

        if cursor.peekKind() == .leftParen {
            cursor.advance()
            let arguments = try parseCallArguments(forOperation: first)
            return makeBareCall(name: first, arguments: arguments)
        }

        cursor.advance()
        var segments = [first]
        while cursor.currentKind == .doubleColon {
            cursor.advance()
            segments.append(try parseNameSegment(describing: "name after '::'"))
        }
        return qualifiedReference(segments)
    }

    /// Builds the node for a name written with `::` separators.
    ///
    /// A single segment is a variable. Inside the arguments of a type operation every
    /// qualified name is a type. Elsewhere `package::Type` is a type and
    /// `package::Enumeration::literal` is an enumeration literal.
    private func qualifiedReference(_ segments: [String]) -> any AQLExpression {
        guard segments.count > 1 else { return AQLVariableExpression(name: segments[0]) }
        let last = segments[segments.count - 1]
        let separator = AQLSyntax.packageSeparator
        if cursor.typeArgumentDepth > 0 || segments.count == 2 {
            return AQLTypeLiteralExpression(
                packageName: segments.dropLast().joined(separator: separator), typeName: last)
        }
        return AQLEnumLiteralExpression(
            packageName: segments.dropLast(2).joined(separator: separator),
            enumName: segments[segments.count - 2], literal: last)
    }

    /// Parses `Kind{element, element}`.
    private mutating func parseCollectionLiteral(kind: String) throws -> any AQLExpression {
        cursor.advance()
        try expect(.leftBrace)
        var elements: [any AQLExpression] = []
        if cursor.currentKind != .rightBrace {
            while true {
                elements.append(try parseExpression())
                guard cursor.currentKind == .comma else { break }
                cursor.advance()
            }
        }
        try expect(.rightBrace)
        let literalKind = AQLCollectionLiteralExpression.Kind(rawValue: kind) ?? .sequence
        return AQLCollectionLiteralExpression(kind: literalKind, elements: elements)
    }

    // MARK: - Calls and lambdas

    /// Parses `(argument, argument)`, where an argument may be a lambda such as `x | body`.
    ///
    /// - Parameters:
    ///   - operation: The name of the operation being called, if any. Arguments of type
    ///     operations denote types.
    ///   - afterArrow: Whether the call follows `->`. Arguments of iterating operations may
    ///     then omit the iterator.
    mutating func parseCallArguments(
        forOperation operation: String? = nil, afterArrow: Bool = false
    ) throws -> [any AQLExpression] {
        try expect(.leftParen)
        let takesTypes = operation.map { AQLSyntax.typeArgumentOperationNames.contains($0) } ?? false
        let iterates = afterArrow && (operation.map { AQLSyntax.iteratorOperationNames.contains($0) } ?? false)
        if takesTypes { cursor.typeArgumentDepth += 1 }
        defer { if takesTypes { cursor.typeArgumentDepth -= 1 } }
        var arguments: [any AQLExpression] = []
        if cursor.currentKind != .rightParen {
            while true {
                arguments.append(try parseCallArgument(iterates: iterates))
                guard cursor.currentKind == .comma else { break }
                cursor.advance()
            }
        }
        try expect(.rightParen)
        return arguments
    }

    /// Parses one call argument, which is a lambda or an expression.
    private mutating func parseCallArgument(iterates: Bool) throws -> any AQLExpression {
        if let header = try parseLambdaHeader() {
            return AQLLambdaExpression(iterator: header.name, body: try parseExpression())
        }
        if iterates {
            cursor.implicitReceiverDepth += 1
            defer { cursor.implicitReceiverDepth -= 1 }
            return AQLLambdaExpression(iterator: AQLSyntax.selfVariable, body: try parseExpression())
        }
        return try parseExpression()
    }

    /// Parses the `x |` or `x : Type |` that starts a lambda, if one is present.
    ///
    /// - Returns: The iterator name and type, or `nil` (with nothing consumed) if there is no
    ///   lambda header.
    mutating func parseLambdaHeader() throws -> (name: String, type: String?)? {
        let saved = cursor.position
        let name: String
        switch cursor.currentKind {
        case .identifier(let text), .keyword(let text):
            name = text
            cursor.advance()
        default:
            return nil
        }

        var type: String?
        if cursor.currentKind == .colon {
            cursor.advance()
            guard let parsed = try? parseTypeName() else {
                cursor.position = saved
                return nil
            }
            type = parsed
        }

        guard cursor.currentKind == .pipe else {
            cursor.position = saved
            return nil
        }
        cursor.advance()
        return (name, type)
    }

    /// Builds the node for a call without an explicit receiver: `name(arguments)`.
    ///
    /// Inside an iterator body, and for OCL type operations, the receiver is the implicit
    /// `self`.
    private mutating func makeBareCall(name: String, arguments: [any AQLExpression]) -> any AQLExpression {
        let implicitSelf = AQLVariableExpression(name: AQLSyntax.selfVariable)
        if AQLSyntax.typeOperationNames.contains(name) {
            return delegate.makeCall(name: name, receiver: implicitSelf, arguments: arguments)
        }
        let appliesToSelf = cursor.implicitReceiverDepth > 0
            && !AQLSyntax.standaloneFunctionNames.contains(name)
        return delegate.makeCall(name: name, receiver: appliesToSelf ? implicitSelf : nil, arguments: arguments)
    }
}
