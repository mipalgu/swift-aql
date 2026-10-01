//
//  AQLStringServices.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The Acceleo/AQL string library.
///
/// All positions are 1-based as in OCL. Regular expressions follow the ICU syntax of
/// `NSRegularExpression` (equivalent to Java regular expressions for common patterns), and
/// replacement strings may refer to groups as `$1`.
///
/// Services: `size` (`length`), `toUpperCase` (`toUpper`, `upper`), `toLowerCase` (`toLower`,
/// `lower`), `toUpperFirst`, `toLowerFirst`, `concat`, `+`, `prefix`, `substring(lower)`,
/// `substring(lower, upper)` (both bounds inclusive), `replace` (first match of a regular
/// expression), `replaceAll`, `substitute` (first literal occurrence), `substituteAll`, `index`,
/// `lastIndex`, `tokenize`, `matches` (whole-string match), `startsWith`, `endsWith`,
/// `equalsIgnoreCase`, `contains`, `strcmp`, `strstr`, `first(n)`, `last(n)`, `at`, `characters`,
/// `isAlpha`, `isAlphanum`, `trim`, `toInteger`, `toReal`, `toBoolean`, and
/// `removeLineSeparators`.
///
/// `replace` and `replaceAll` take a regular expression; `substitute` (`substituteFirst`) and
/// `substituteAll` treat their first argument and the replacement as literal text, so that
/// characters such as `.` and `$` have no special meaning. `index` and `lastIndex` return -1 when
/// the substring is absent.
///
/// The standard library has no services to split text into lines, join or indent text, or convert
/// between characters and character codes or radix strings. The nearest standard equivalents are
/// `tokenize` with a delimiter string (which drops empty tokens) for splitting, `sep` on
/// collections for interleaving separators, `characters` for individual characters, and
/// `toString` for any value. Such helpers belong in the service set of the template library that
/// needs them.
public struct AQLStringServices: AQLServiceProvider {
    /// Creates the provider.
    public init() {}

    // MARK: - Helpers

    private static let defaultDelimiters = " \t\n\r\u{0C}"

    private static func regex(_ pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw AQLExecutionError.invalidOperation("Invalid regular expression '\(pattern)'")
        }
    }

    private static func replaceFirst(in text: String, pattern: String, with template: String) throws -> String {
        let expression = try regex(pattern)
        let nsText = text as NSString
        guard let match = expression.firstMatch(
            in: text, range: NSRange(location: 0, length: nsText.length))
        else { return text }
        let replacement = expression.replacementString(
            for: match, in: text, offset: 0, template: template)
        return nsText.replacingCharacters(in: match.range, with: replacement)
    }

    private static func replaceAll(in text: String, pattern: String, with template: String) throws -> String {
        let expression = try regex(pattern)
        return expression.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template)
    }

    private static func matchesWhole(_ text: String, pattern: String) throws -> Bool {
        try regex("\\A(?:\(pattern))\\z").firstMatch(
            in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// 1-based index of the first occurrence at or after the 0-based `from`, or -1.
    private static func index(of needle: String, in text: String, from: Int) -> Int {
        let characters = Array(text)
        let start = Swift.max(0, from)
        guard start <= characters.count else { return -1 }
        if needle.isEmpty { return start + 1 }
        let tail = String(characters[start...])
        guard let range = tail.range(of: needle) else { return -1 }
        return start + tail.distance(from: tail.startIndex, to: range.lowerBound) + 1
    }

    /// 1-based index of the last occurrence starting at or before the 0-based `from`, or -1.
    private static func lastIndex(of needle: String, in text: String, from: Int) -> Int {
        let characters = Array(text)
        guard from >= 0 else { return -1 }
        if needle.isEmpty { return Swift.min(from, characters.count) + 1 }
        let limit = Swift.min(characters.count, from + needle.count)
        let head = String(characters[..<limit])
        guard let range = head.range(of: needle, options: .backwards) else { return -1 }
        return head.distance(from: head.startIndex, to: range.lowerBound) + 1
    }

    private static func tokens(_ text: String, delimiters: String) -> [any EcoreValue] {
        let separators = Set(delimiters)
        return text.split(whereSeparator: { separators.contains($0) }).map { String($0) }
    }

    private static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs.utf16)
        let right = Array(rhs.utf16)
        for (a, b) in zip(left, right) where a != b { return Int(a) - Int(b) }
        return left.count - right.count
    }

    private static func capitalise(_ text: String, upper: Bool) -> String {
        guard let first = text.first else { return text }
        let head = upper ? String(first).uppercased() : String(first).lowercased()
        return head + text.dropFirst()
    }

    private static func isLetter(_ character: Character) -> Bool { character.isLetter }

    // MARK: - Services

    /// The services offered.
    public var services: [AQLService] {
        let s = AQLReceiver.string
        var list: [AQLService] = []
        func add(_ names: [String], arity: ClosedRange<Int> = 0...0, _ body: @escaping AQLServiceImplementation) {
            for name in names { list.append(AQLService(name, receiver: s, arity: arity, implementation: body)) }
        }

        add(["size", "length"]) { try $0.receiverString().count }
        add(["toUpperCase", "toUpper", "upper"]) { try $0.receiverString().uppercased() }
        add(["toLowerCase", "toLower", "lower"]) { try $0.receiverString().lowercased() }
        add(["toUpperFirst"]) { Self.capitalise(try $0.receiverString(), upper: true) }
        add(["toLowerFirst"]) { Self.capitalise(try $0.receiverString(), upper: false) }
        add(["concat", "+"], arity: 1...1) { try $0.receiverString() + $0.string(0) }
        add(["prefix"], arity: 1...1) { try $0.string(0) + $0.receiverString() }
        add(["substring"], arity: 1...2) { call in
            let characters = Array(try call.receiverString())
            let lower = try call.integer(0)
            let upper = call.arguments.count > 1 ? try call.integer(1) : characters.count
            guard lower >= 1, lower - 1 <= upper, upper <= characters.count else { return nil }
            return String(characters[(lower - 1)..<upper])
        }
        add(["replace"], arity: 2...2) {
            try Self.replaceFirst(in: $0.receiverString(), pattern: $0.string(0), with: $0.string(1))
        }
        add(["replaceAll"], arity: 2...2) {
            try Self.replaceAll(in: $0.receiverString(), pattern: $0.string(0), with: $0.string(1))
        }
        add(["substitute", "substituteFirst"], arity: 2...2) { call in
            let text = try call.receiverString()
            guard let range = text.range(of: try call.string(0)) else { return text }
            return text.replacingCharacters(in: range, with: try call.string(1))
        }
        add(["substituteAll"], arity: 2...2) {
            try $0.receiverString().replacingOccurrences(of: $0.string(0), with: $0.string(1))
        }
        add(["index"], arity: 1...2) { call in
            Self.index(
                of: try call.string(0), in: try call.receiverString(),
                from: call.arguments.count > 1 ? try call.integer(1) : 0)
        }
        add(["lastIndex"], arity: 1...2) { call in
            let text = try call.receiverString()
            return Self.lastIndex(
                of: try call.string(0), in: text,
                from: call.arguments.count > 1 ? try call.integer(1) : text.count)
        }
        add(["tokenize"], arity: 0...1) { call in
            EcoreValueArray(
                Self.tokens(
                    try call.receiverString(),
                    delimiters: call.arguments.isEmpty ? Self.defaultDelimiters : try call.string(0)))
        }
        add(["matches"], arity: 1...1) { try Self.matchesWhole(try $0.receiverString(), pattern: $0.string(0)) }
        add(["startsWith"], arity: 1...1) { try $0.receiverString().hasPrefix($0.string(0)) }
        add(["endsWith"], arity: 1...1) { try $0.receiverString().hasSuffix($0.string(0)) }
        add(["equalsIgnoreCase"], arity: 1...1) {
            try $0.receiverString().lowercased() == $0.string(0).lowercased()
        }
        add(["contains", "strstr"], arity: 1...1) { call in
            let needle = try call.string(0)
            return try needle.isEmpty || call.receiverString().contains(needle)
        }
        add(["strcmp"], arity: 1...1) { Self.compare(try $0.receiverString(), try $0.string(0)) }
        add(["first"], arity: 1...1) { call in
            let text = try call.receiverString()
            let count = try call.integer(0)
            guard count >= 0 else { return nil }
            return String(text.prefix(count))
        }
        add(["last"], arity: 1...1) { call in
            let text = try call.receiverString()
            let count = try call.integer(0)
            guard count >= 0 else { return nil }
            return String(text.suffix(count))
        }
        add(["at"], arity: 1...1) { call in
            let characters = Array(try call.receiverString())
            let position = try call.integer(0)
            guard position >= 1, position <= characters.count else { return nil }
            return String(characters[position - 1])
        }
        add(["characters"]) { EcoreValueArray(try $0.receiverString().map { String($0) }) }
        add(["isAlpha"]) { try $0.receiverString().allSatisfy(Self.isLetter) }
        add(["isAlphanum", "isAlphaNum"]) { try $0.receiverString().allSatisfy { $0.isLetter || $0.isNumber } }
        add(["trim"]) { try $0.receiverString().trimmingCharacters(in: .whitespacesAndNewlines) }
        add(["toInteger"]) { Int(try $0.receiverString().trimmingCharacters(in: .whitespaces)) }
        add(["toReal"]) { Double(try $0.receiverString().trimmingCharacters(in: .whitespaces)) }
        add(["toBoolean"]) { try $0.receiverString().lowercased() == "true" }
        add(["removeLineSeparators"]) {
            try $0.receiverString().replacingOccurrences(of: "[\\r\\n]", with: "", options: .regularExpression)
        }
        return list
    }
}
