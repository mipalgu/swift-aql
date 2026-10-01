//
//  AQLStringServicesTests.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import Testing

@testable import AQL

@MainActor
@Suite("AQL String services")
struct AQLStringServicesTests {
    nonisolated static let cases: [LibraryCase] = [
        LibraryCase("HelloWorld", "size", expect: 10),
        LibraryCase("HelloWorld", "length", expect: 10),
        LibraryCase("HelloWorld", "toUpper", expect: "HELLOWORLD"),
        LibraryCase("HelloWorld", "toUpperCase", expect: "HELLOWORLD"),
        LibraryCase("HelloWorld", "toLower", expect: "helloworld"),
        LibraryCase("HelloWorld", "toLowerCase", expect: "helloworld"),
        LibraryCase("helloworld", "toUpperFirst", expect: "Helloworld"),
        LibraryCase("HelloWorld", "toLowerFirst", expect: "helloWorld"),
        LibraryCase("", "toUpperFirst", expect: ""),
        LibraryCase("Hello", "concat", "World", expect: "HelloWorld"),
        LibraryCase("Hello", "+", "World", expect: "HelloWorld"),
        LibraryCase("World", "prefix", "Hello", expect: "HelloWorld"),
        LibraryCase("HelloWorld", "substring", 5, expect: "oWorld"),
        LibraryCase("HelloWorld", "substring", 1, expect: "HelloWorld"),
        LibraryCase("HelloWorld", "substring", 1, 5, expect: "Hello"),
        LibraryCase("HelloWorld", "substring", 6, 10, expect: "World"),
        LibraryCase("HelloWorld", "substring", 0, 5, expect: nil),
        LibraryCase("HelloWorld", "substring", 3, 99, expect: nil),
        LibraryCase("Hello", "replace", "l+", "L", expect: "HeLo"),
        LibraryCase("hello world", "replace", "world", "Swift", expect: "hello Swift"),
        LibraryCase("aXbXc", "replace", "X", "-", expect: "a-bXc"),
        LibraryCase("a1b22", "replaceAll", "[0-9]+", "#", expect: "a#b#"),
        LibraryCase("john smith", "replaceAll", "(\\w+) (\\w+)", "$2 $1", expect: "smith john"),
        LibraryCase("WorldWorld", "substitute", "World", "Hello", expect: "HelloWorld"),
        LibraryCase("WorldWorld", "substituteAll", "World", "Hello", expect: "HelloHello"),
        LibraryCase("a.b.c", "substituteAll", ".", "/", expect: "a/b/c"),
        LibraryCase("HelloHello", "index", "Hello", expect: 1),
        LibraryCase("HelloHello", "index", "Hello", 2, expect: 6),
        LibraryCase("HelloHello", "index", "World", expect: -1),
        LibraryCase("HelloHello", "lastIndex", "Hello", expect: 6),
        LibraryCase("HelloHello", "lastIndex", "World", expect: -1),
        LibraryCase("a, b, c, d", "tokenize", ", ", expect: seq("a", "b", "c", "d")),
        LibraryCase("a, b, c, d", "tokenize", expect: seq("a,", "b,", "c,", "d")),
        LibraryCase("Hello", "matches", "H.*o", expect: true),
        LibraryCase("Hello", "matches", "ell", expect: false),
        LibraryCase("Hello", "startsWith", "Hell", expect: true),
        LibraryCase("Hello", "startsWith", "ell", expect: false),
        LibraryCase("Hello", "endsWith", "llo", expect: true),
        LibraryCase("Hello", "equalsIgnoreCase", "hELLO", expect: true),
        LibraryCase("Hello", "equalsIgnoreCase", "Help", expect: false),
        LibraryCase("Hello", "contains", "llo", expect: true),
        LibraryCase("Hello", "contains", "xyz", expect: false),
        LibraryCase("strcmp operation", "strcmp", "strcmp", expect: 10),
        LibraryCase("strcmp operation", "strcmp", "strcmp operation", expect: 0),
        LibraryCase("strcmp operation", "strcmp", "strtok", expect: -17),
        LibraryCase("HelloWorld", "strstr", "World", expect: true),
        LibraryCase("HelloWorld", "first", 5, expect: "Hello"),
        LibraryCase("Hi", "first", 5, expect: "Hi"),
        LibraryCase("HelloWorld", "last", 5, expect: "World"),
        LibraryCase("Hi", "last", 5, expect: "Hi"),
        LibraryCase("cat", "at", 2, expect: "a"),
        LibraryCase("cat", "characters", expect: seq("c", "a", "t")),
        LibraryCase("abcdef", "isAlpha", expect: true),
        LibraryCase("abc123", "isAlpha", expect: false),
        LibraryCase("abc123", "isAlphanum", expect: true),
        LibraryCase("abc 123", "isAlphanum", expect: false),
        LibraryCase("  Hello World   ", "trim", expect: "Hello World"),
        LibraryCase("42", "toInteger", expect: 42),
        LibraryCase("41.9", "toReal", expect: 41.9),
        LibraryCase("True", "toBoolean", expect: true),
        LibraryCase("Some", "toBoolean", expect: false),
        LibraryCase("Hello\nWorld", "removeLineSeparators", expect: "HelloWorld"),
        LibraryCase("abc", "toString", expect: "abc"),
        LibraryCase(nil, "lineSeparator", expect: "\n"),
    ]

    @Test("String library behaviour", arguments: cases)
    func library(_ test: LibraryCase) async throws {
        try await check(test)
    }

    @Test("Invalid regular expression is reported")
    func invalidRegex() async throws {
        await #expect(throws: AQLExecutionError.self) {
            _ = try await evaluate(LibraryCase("a", "matches", "(", expect: nil))
        }
    }

    @Test("Wrong argument type is reported")
    func wrongArgument() async throws {
        await #expect(throws: AQLExecutionError.self) {
            _ = try await evaluate(LibraryCase("a", "concat", 1, expect: nil))
        }
    }

    @Test("Standalone call treats first argument as receiver")
    func standaloneForm() async throws {
        let expr = AQLCallExpression(methodName: "toUpper", arguments: [lit("abc")])
        let result = try await expr.evaluate(in: makeContext())
        #expect(result as? String == "ABC")
    }
}
