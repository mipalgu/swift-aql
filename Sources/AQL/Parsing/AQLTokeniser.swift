//
//  AQLTokeniser.swift
//  AQL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// The tokens of a piece of AQL text together with the problems found while reading it.
public struct AQLTokenisation: Sendable, Equatable {
    /// The tokens in order, including comments and invalid tokens but not the end of input.
    public var tokens: [AQLToken]

    /// The lexical problems in order of position.
    public var diagnostics: [AQLDiagnostic]
}

/// Splits AQL text into tokens.
///
/// The tokeniser never fails: text that is not a valid token becomes an
/// ``AQLTokenKind/invalid(_:)`` token and adds a diagnostic, and reading continues after it.
struct AQLTokeniser {

    // MARK: - State

    /// The characters of the text.
    private let characters: [Character]

    /// The UTF-8 offset of each character, followed by the offset of the end of the text.
    private let offsets: [Int]

    /// The index of the next character.
    private var index = 0

    /// The line of the next character.
    private var line = 1

    /// The column of the next character.
    private var column = 1

    /// The tokens read so far.
    private var tokens: [AQLToken] = []

    /// The problems found so far.
    private var diagnostics: [AQLDiagnostic] = []

    // MARK: - Entry point

    /// Splits text into tokens.
    ///
    /// - Parameter text: The AQL text.
    /// - Returns: The tokens and the lexical problems.
    static func tokenise(_ text: String) -> AQLTokenisation {
        var tokeniser = AQLTokeniser(text)
        tokeniser.run()
        return AQLTokenisation(tokens: tokeniser.tokens, diagnostics: tokeniser.diagnostics)
    }

    private init(_ text: String) {
        characters = Array(text)
        var offsets: [Int] = []
        offsets.reserveCapacity(characters.count + 1)
        var offset = 0
        for character in characters {
            offsets.append(offset)
            offset += character.utf8.count
        }
        offsets.append(offset)
        self.offsets = offsets
    }

    // MARK: - Reading

    private mutating func run() {
        while true {
            skipWhitespace()
            guard let character = current else { return }
            let start = mark()
            if character == "-", next == "-" {
                readComment(start)
            } else if character == AQLSyntax.stringDelimiter {
                readString(start)
            } else if character.isNumber
                || (character == "-" && next?.isNumber == true && !endsOperand(tokens.last)) {
                readNumber(start)
            } else if character.isLetter || character == "_" {
                readWord(start)
            } else {
                readPunctuation(start)
            }
        }
    }

    /// The position at which a token starts.
    private struct Mark {
        let index: Int
        let line: Int
        let column: Int
    }

    private func mark() -> Mark { Mark(index: index, line: line, column: column) }

    private var current: Character? { index < characters.count ? characters[index] : nil }

    private var next: Character? { index + 1 < characters.count ? characters[index + 1] : nil }

    private mutating func advance() {
        guard index < characters.count else { return }
        if characters[index].isNewline {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private mutating func skipWhitespace() {
        while let character = current, character.isWhitespace { advance() }
    }

    private func span(from start: Mark) -> AQLSourceSpan {
        AQLSourceSpan(
            line: start.line, column: start.column, offset: offsets[start.index],
            length: offsets[index] - offsets[start.index])
    }

    private mutating func emit(_ kind: AQLTokenKind, from start: Mark) {
        tokens.append(AQLToken(kind: kind, span: span(from: start)))
    }

    private mutating func report(_ code: String, _ message: String, at start: Mark) {
        diagnostics.append(AQLDiagnostic(code: code, message: message, span: span(from: start)))
    }

    /// Whether the token ends an operand, so that a following minus sign is binary.
    private func endsOperand(_ token: AQLToken?) -> Bool {
        switch token?.kind {
        case .identifier, .integerLiteral, .realLiteral, .stringLiteral, .booleanLiteral,
            .rightParen, .rightBrace:
            return true
        case .keyword(let word):
            return !AQLSyntax.operandExpectingKeywords.contains(word)
        default:
            return false
        }
    }

    private mutating func readComment(_ start: Mark) {
        advance()
        advance()
        var text = ""
        while let character = current, !character.isNewline {
            text.append(character)
            advance()
        }
        emit(.comment(text.trimmingBlanks()), from: start)
    }

    private mutating func readNumber(_ start: Mark) {
        var text = ""
        var hasDecimal = false
        if current == "-" {
            text.append("-")
            advance()
        }
        while let character = current {
            if character.isNumber {
                text.append(character)
                advance()
            } else if character == ".", !hasDecimal, next?.isNumber == true {
                hasDecimal = true
                text.append(character)
                advance()
            } else {
                break
            }
        }
        if hasDecimal {
            if let value = Double(text) {
                emit(.realLiteral(value), from: start)
            } else {
                emit(.invalid(text), from: start)
                report(AQLDiagnosticCode.invalidNumber, "Invalid real number: \(text)", at: start)
            }
        } else if let value = Int(text) {
            emit(.integerLiteral(value), from: start)
        } else {
            emit(.invalid(text), from: start)
            report(AQLDiagnosticCode.invalidNumber, "Invalid integer: \(text)", at: start)
        }
    }

    private mutating func readWord(_ start: Mark) {
        var word = ""
        while let character = current, character.isLetter || character.isNumber || character == "_" {
            word.append(character)
            advance()
        }
        switch word {
        case AQLSyntax.trueLiteral: emit(.booleanLiteral(true), from: start)
        case AQLSyntax.falseLiteral: emit(.booleanLiteral(false), from: start)
        case _ where AQLSyntax.keywords.contains(word): emit(.keyword(word), from: start)
        default: emit(.identifier(word), from: start)
        }
    }

    private mutating func readString(_ start: Mark) {
        advance()
        var text = ""
        var problem: (code: String, message: String)?
        while let character = current {
            if character == AQLSyntax.stringDelimiter {
                if next == AQLSyntax.stringDelimiter {
                    text.append(AQLSyntax.stringDelimiter)
                    advance()
                    advance()
                    continue
                }
                advance()
                finishString(text, problem, start)
                return
            }
            guard character == "\\" else {
                text.append(character)
                advance()
                continue
            }
            advance()
            guard let escaped = current else { break }
            switch escaped {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "r": text.append("\r")
            case "b": text.append("\u{08}")
            case "f": text.append("\u{0C}")
            case "u":
                if let resolved = readUnicodeEscape() {
                    text.append(resolved)
                } else {
                    problem = problem ?? (
                        AQLDiagnosticCode.malformedEscape, "Malformed unicode escape in string literal")
                }
                continue
            default: text.append(escaped)
            }
            advance()
        }
        emit(.invalid(String(characters[start.index..<index])), from: start)
        report(AQLDiagnosticCode.unterminatedString, "Unterminated string literal", at: start)
    }

    private mutating func finishString(
        _ text: String, _ problem: (code: String, message: String)?, _ start: Mark
    ) {
        if let problem {
            emit(.invalid(String(characters[start.index..<index])), from: start)
            report(problem.code, problem.message, at: start)
        } else {
            emit(.stringLiteral(text), from: start)
        }
    }

    /// Reads a `\uXXXX` escape with the cursor on the `u`.
    ///
    /// A high surrogate followed by an escaped low surrogate combines into one character; an
    /// unpaired surrogate becomes the replacement character.
    ///
    /// - Returns: The character the escape denotes, or `nil` if fewer than four hexadecimal
    ///   digits follow.
    private mutating func readUnicodeEscape() -> Character? {
        guard let first = readCodeUnit() else { return nil }
        if (0xD800...0xDBFF).contains(first), current == "\\" {
            let resume = (index, line, column)
            advance()
            if current == "u" {
                guard let second = readCodeUnit() else { return nil }
                if (0xDC00...0xDFFF).contains(second),
                    let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
                {
                    return Character(scalar)
                }
            }
            (index, line, column) = resume
            return "\u{FFFD}"
        }
        return Unicode.Scalar(first).map(Character.init) ?? "\u{FFFD}"
    }

    private mutating func readCodeUnit() -> UInt32? {
        advance()
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let character = current, let digit = character.hexDigitValue else { return nil }
            value = value * 16 + UInt32(digit)
            advance()
        }
        return value
    }

    private mutating func readPunctuation(_ start: Mark) {
        guard let character = current else { return }
        let pair = next.map { String([character, $0]) }
        switch pair {
        case AQLSyntax.arrow, AQLSyntax.notEquals, AQLSyntax.lessOrEqual, AQLSyntax.greaterOrEqual:
            advance()
            advance()
            emit(.operator(pair ?? ""), from: start)
            return
        case "::":
            advance()
            advance()
            emit(.doubleColon, from: start)
            return
        default:
            break
        }
        advance()
        switch character {
        case "/": emit(.slash, from: start)
        case "(": emit(.leftParen, from: start)
        case ")": emit(.rightParen, from: start)
        case ",": emit(.comma, from: start)
        case ":": emit(.colon, from: start)
        case "{": emit(.leftBrace, from: start)
        case "}": emit(.rightBrace, from: start)
        case ".": emit(.dot, from: start)
        case "|": emit(.pipe, from: start)
        case "?": emit(.questionMark, from: start)
        case "+", "-", "*", "=", "<", ">": emit(.operator(String(character)), from: start)
        default:
            emit(.invalid(String(character)), from: start)
            report(AQLDiagnosticCode.invalidCharacter, "Unexpected character: '\(character)'", at: start)
        }
    }
}

extension String {
    /// The string without leading and trailing spaces and tabs.
    fileprivate func trimmingBlanks() -> String {
        let blanks: Set<Character> = [" ", "\t"]
        guard let first = firstIndex(where: { !blanks.contains($0) }),
            let last = lastIndex(where: { !blanks.contains($0) })
        else { return "" }
        return String(self[first...last])
    }
}
