//
//  AQLParserTestSupport.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase

@testable import AQL

/// A node standing for a call that a host resolves itself, as a template language would.
struct InvocationProbe: AQLExpression {
    let name: String
    let receiver: (any AQLExpression)?
    let arguments: [any AQLExpression]

    @MainActor
    func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? { nil }
}

/// A node standing for a host construct that names a set, such as `collected('set')`.
struct CollectedProbe: AQLExpression {
    let setName: any AQLExpression

    @MainActor
    func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? { nil }
}

/// A delegate that behaves like a template language host.
///
/// Calls to the OCL type operations stay plain AQL calls and every other call becomes an
/// ``InvocationProbe``. The construct `collected(expression)` is a primary expression.
struct HostProbeDelegate: AQLParserDelegate {
    /// The names offered to ``parsePrimary(named:cursor:)``, in order.
    var offered: [String] = []

    mutating func makeCall(
        name: String, receiver: (any AQLExpression)?, arguments: [any AQLExpression],
        origin: SourceOrigin
    ) -> any AQLExpression {
        if AQLSyntax.typeOperationNames.contains(name) {
            return AQLCallExpression(source: receiver, methodName: name, arguments: arguments, origin: origin)
        }
        return InvocationProbe(name: name, receiver: receiver, arguments: arguments)
    }

    mutating func parsePrimary(named name: String, cursor: inout AQLTokenCursor) throws
        -> (any AQLExpression)?
    {
        offered.append(name)
        guard name == "collected", cursor.peekKind() == .leftParen else { return nil }
        cursor.advance()
        cursor.advance()
        let setName = try AQLParser.parseExpression(&cursor, delegate: &self)
        try cursor.expect(.rightParen)
        return CollectedProbe(setName: setName)
    }
}

/// Parsing helpers shared by the parser tests.
enum AQLParserTestSupport {

    /// The printer for trees with the host nodes of ``HostProbeDelegate``.
    static let printer = AQLTreePrinter { expression, printer in
        switch expression {
        case let node as InvocationProbe:
            return "invoke(\(printer.optional(node.receiver)), \(node.name), "
                + "args: \(printer.list(node.arguments)))"
        case let node as CollectedProbe:
            return "collected(\(printer.print(node.setName)))"
        default:
            return nil
        }
    }

    /// Parses text with the host delegate and prints the tree, or returns `nil` on error.
    static func tree(_ source: String) -> String? {
        var delegate = HostProbeDelegate()
        guard let expression = AQLParser().parse(source, delegate: &delegate).expression else { return nil }
        return printer.print(expression)
    }

    /// Parses text with the default delegate and prints the tree, or returns `nil` on error.
    static func plainTree(_ source: String) -> String? {
        AQLParser().parse(source).expression.map { AQLTreePrinter().print($0) }
    }
}

/// A start position and length in the form the parser tests compare.
struct Span: Equatable {
    var line: Int
    var column: Int
    var offset: Int
    var length: Int = 0

    init(line: Int, column: Int, offset: Int = 0, length: Int = 0) {
        self.line = line
        self.column = column
        self.offset = offset
        self.length = length
    }
}

extension SourceRange {
    /// The range as a ``Span``.
    var span: Span {
        Span(line: start.line, column: start.column, offset: start.utf8Offset, length: utf8Length)
    }

    /// An empty range at the given line and column.
    static func at(line: Int, column: Int) -> SourceRange {
        let position = SourcePosition(utf8Offset: column - 1, line: line, column: column)
        return SourceRange(start: position, end: position)
    }
}
