//
//  OCLToAQLTranslatorTests.swift
//  AQLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OCL
import Testing

@testable import AQL

@MainActor
@Suite("OCL to AQL translation")
struct OCLToAQLTranslatorTests {
    /// The translator with the library metamodel.
    static func translator() async -> OCLToAQLTranslator {
        OCLToAQLTranslator(packages: [await OCLLibraryFixture().package])
    }

    @Test("Translations of the common subset", arguments: [
        ("self.books->size() > 0", "self.books->size() > 0"),
        ("books->select(b | b.copies > 1)", "books->select(b | b.copies > 1)"),
        ("books->select(copies > 1)", "books->select(copies > 1)"),
        ("books->select(title = self.name)", "let oclSelf = self in books->select(title = oclSelf.name)"),
        ("books->forAll(a, b | a <> b implies a.title <> b.title)",
         "(let oclSource1 = books in oclSource1->forAll(a | oclSource1->forAll(b | (a <> b) implies (a.title <> b.title))))"),
        ("genre = Genre::fiction", "genre = lib::Genre::fiction"),
        ("Book.allInstances()->size()", "lib::Book.allInstances()->size()"),
        ("isAvailable()", "self.isAvailable()"),
        ("7 / 2", "7 * 1.0 / 2"),
        ("-x.abs()", "-(x.abs())"),
        ("-3", "-(3)"),
        ("- (a + b)", "-(a + b)"),
        ("if a then 1 elseif b then 2 else 3 endif", "if a then 1 else if b then 2 else 3 endif endif"),
        ("let a : Integer = 1, b = a + 1 in b", "let a = 1 in let b = a + 1 in b"),
        ("self.oclType().name", "self.eClass().name"),
        ("books->selectByKind(Book)", "books->filter(Book)"),
        ("books->selectByType(Book)", "books->select(e | e.oclIsTypeOf(Book))"),
        ("books?->collect(title)", "books->excluding(null)->collect(title)"),
        ("'it\\'s'", "'it\\'s'"),
        ("'a' 'b'", "'ab'"),
        ("1e3", "1000.0"),
        ("Set{1, 2}->including(3)", "Set{1, 2}->including(3)"),
        ("not (a and b)", "not (a and b)"),
        ("x.oclIsKindOf(lib::Book)", "x.oclIsKindOf(lib::Book)"),
    ])
    func translations(_ ocl: String, _ aql: String) async throws {
        let translation = await Self.translator().translate(ocl)
        #expect(translation.aql == aql, "\(translation.diagnostics.map(\.message))")
        let text = try #require(translation.aql)
        #expect(AQLParser().parse(text).diagnostics.isEmpty)
    }

    @Test("Translated expressions evaluate as in OCL", arguments: [
        ("books->size() = 2", true as Bool?),
        ("self.books->forAll(b | b.copies > 1)", true),
        ("books->exists(genre = Genre::science)", true),
        ("books->select(genre = Genre::fiction)->size() = 1", true),
        ("books->select(title <> self.name)->size() = 2", true),
        ("books->forAll(b1, b2 | b1 <> b2 implies b1.title <> b2.title)", true),
        ("books->exists(b1, b2 | b1 <> b2 and b1.copies = b2.copies)", false),
        ("books->isUnique(title)", true),
        ("books->one(copies = 2)", true),
        ("books->collect(copies)->sum() = 5", true),
        ("books.copies->sum() = 5", true),
        ("books.tags->size() = 3", true),
        ("books->any(copies = 3).title = 'Beta'", true),
        ("books->sortedBy(b | b.copies)->first().title = 'Alpha'", true),
        ("7 / 2 = 3.5", true),
        ("7.div(2) = 3 and 7.mod(2) = 1", true),
        ("-3.abs() = -3", true),
        ("let n = books->size() in n * 2 = 4", true),
        ("if books->isEmpty() then false else true endif", true),
        ("name.size() = 4 and name.toUpperCase() = 'CITY'", true),
        ("name.substring(1, 2) = 'Ci'", true),
        ("Book.allInstances()->size() = 2", true),
        ("self.oclIsKindOf(Library) and not self.oclIsKindOf(Book)", true),
        ("self.oclType().name = 'Library'", true),
        ("books->selectByKind(Book)->size() = 2", true),
        ("Set{1, 2, 2}->size() = 2 and Bag{1, 2, 2}->size() = 3", true),
        ("books->collectNested(tags)->size() = 3", true),
        ("true xor false", true),
        ("false implies null", true),
        ("name->notEmpty()", true),
        ("books->reject(copies = 2)->size() = 1", true),
    ])
    func evaluation(_ ocl: String, _ expected: Bool?) async throws {
        let fixture = await OCLLibraryFixture()
        let value = try await fixture.evaluate(ocl)
        #expect(value as? Bool == expected, "\(ocl) gave \(AQLValues.description(of: value))")
    }

    @Test("An invariant evaluates for each book")
    func perObject() async throws {
        let fixture = await OCLLibraryFixture()
        #expect(try await fixture.evaluate("copies <= 2", for: fixture.books[0]) as? Bool == true)
        #expect(try await fixture.evaluate("copies <= 2", for: fixture.books[1]) as? Bool == false)
        #expect(try await fixture.evaluate("tags->includes('x')", for: fixture.books[0]) as? Bool == true)
    }

    @Test("Constructs without an AQL counterpart are reported", arguments: [
        "books->iterate(b; n : Integer = 0 | n + b.copies)", "Tuple{a = 1}.a", "Map{1 with 2}", "Sequence{1..3}",
        "count@pre", "invalid", "x.oclIsInvalid()", "Lambda{1}", "a[1]", "Point{x = 1}", "*", "a and2 b",
        "Kind::of()", "books->collect(b, c | b)", "x.foo(y | y)", "books->forAll()",
    ])
    func untranslatable(_ ocl: String) async throws {
        let translation = await Self.translator().translate(ocl)
        #expect(translation.aql == nil)
        #expect(translation.diagnostics.contains { $0.code == OCLDiagnosticCode.untranslatable || $0.severity == .error })
    }

    @Test("Translations whose meaning can differ carry a note", arguments: [
        ("books->collectNested(tags)", DiagnosticSeverity.warning),
        ("name.lastIndexOf('y')", .warning),
        ("name.indexOf('y')", .information),
        ("a?.b", .information),
        ("isAvailable()", .information),
        ("Collection{1}", .warning),
        ("Shade::dark = x", .warning),
        ("Unknown.allInstances()", .warning),
    ])
    func gaps(_ ocl: String, _ severity: DiagnosticSeverity) async throws {
        let translation = await Self.translator().translate(ocl)
        #expect(translation.aql != nil)
        #expect(translation.diagnostics.contains { $0.code == OCLDiagnosticCode.semanticGap && $0.severity == severity })
    }

    @Test("Without packages, qualified names are kept")
    func withoutPackages() {
        let translation = OCLToAQLTranslator().translate("genre = Genre::fiction")
        #expect(translation.aql == "genre = Genre::fiction")
        #expect(translation.diagnostics.isEmpty)
    }

    @Test("Syntax errors are passed on")
    func syntaxErrors() {
        let translation = OCLToAQLTranslator().translate("a and")
        #expect(translation.aql == nil)
        #expect(translation.diagnostics.first?.code == OCLDiagnosticCode.unexpectedEnd)
    }
}
