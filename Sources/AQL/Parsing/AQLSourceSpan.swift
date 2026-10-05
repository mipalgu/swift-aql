//
//  AQLSourceSpan.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// A stretch of source text, located by line, column, and UTF-8 offset.
///
/// All positions in the AQL parser are expressed through this one type, so that a different
/// position representation can replace it in one place. Lines and columns start at 1 and
/// count characters (extended grapheme clusters); the offset counts UTF-8 code units from the
/// start of the text and starts at 0.
public struct AQLSourceSpan: Sendable, Equatable, Hashable {
    /// The line on which the span starts, counting from 1.
    public var line: Int

    /// The column at which the span starts, counting characters from 1.
    public var column: Int

    /// The UTF-8 offset at which the span starts, counting from 0.
    public var offset: Int

    /// The number of UTF-8 code units in the span.
    public var length: Int

    /// Creates a span.
    ///
    /// - Parameters:
    ///   - line: The line on which the span starts, counting from 1.
    ///   - column: The column at which the span starts, counting from 1.
    ///   - offset: The UTF-8 offset at which the span starts, counting from 0.
    ///   - length: The number of UTF-8 code units in the span.
    public init(line: Int, column: Int, offset: Int = 0, length: Int = 0) {
        self.line = line
        self.column = column
        self.offset = offset
        self.length = length
    }

    /// The UTF-8 offset just after the span.
    public var endOffset: Int { offset + length }
}
