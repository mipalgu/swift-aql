//
//  AQLOptionsSemanticsTests.swift
//  AQL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import AQL

@Suite("AQL options from semantics")
struct AQLOptionsSemanticsTests {
    /// The name of the environment variable, as documented.
    private let variable = "SWIFT_MODELLING_SEMANTICS"

    @Test("each semantics selects its preset")
    func presets() {
        #expect(AQLOptions(semantics: .standard) == .standard)
        #expect(AQLOptions(semantics: .legacy) == .legacy)
    }

    @Test("the environment selects the preset", arguments: ModellingSemantics.allCases)
    func environment(semantics: ModellingSemantics) throws {
        #expect(try AQLOptions.fromEnvironment([variable: semantics.rawValue]) == AQLOptions(semantics: semantics))
    }

    @Test("without a choice in the environment, the options are standard")
    func unset() throws {
        #expect(try AQLOptions.fromEnvironment([:]) == .standard)
        #expect(try AQLOptions.fromEnvironment([variable: ""]) == .standard)
    }

    @Test("an invalid value in the environment is an error")
    func invalid() {
        #expect(throws: ModellingSemanticsError.invalidValue("eclipse", variable: variable)) {
            try AQLOptions.fromEnvironment([variable: "eclipse"])
        }
    }

    @Test("the process environment is read by default")
    func processEnvironment() throws {
        let expected = try AQLOptions.fromEnvironment(ProcessInfo.processInfo.environment)
        #expect(try AQLOptions.fromEnvironment() == expected)
    }
}
