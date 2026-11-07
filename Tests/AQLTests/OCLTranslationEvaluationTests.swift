//
//  OCLTranslationEvaluationTests.swift
//  AQLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OCL
import Testing

@testable import AQL

/// Self-authored OCLinEcore and Complete OCL documents for the tests of the translation into AQL.
enum OCLTranslationFixtures {
    /// A school model in the writer's layout, which exercises every construct the writer emits.
    static let school = """
        import ecore : 'http://www.eclipse.org/emf/2002/Ecore#/';

        package school : sch = 'http://example.org/school'
        {
        \tdocumentation 'A neutral school model for tests.';
        \tpackage records : rec = 'http://example.org/school/records'
        \t{
        \t\tclass Transcript;
        \t}
        \tenum Level
        \t{
        \t\tliteral introductory;
        \t\tliteral advanced = 5;
        \t\tliteral research : 'Research';
        \t}
        \tdatatype Code : 'java.lang.String' { serializable }
        \t{
        \t\tinvariant WellFormed: self.size() = 6;
        \t}
        \tabstract class Named
        \t{
        \t\tattribute name : String;
        \t\tattribute nickname : String[?];
        \t}
        \tclass School extends Named
        \t{
        \t\tproperty courses#school : Course[*] { composes, ordered };
        \t\tproperty students : Student[*] { composes }
        \t\t{
        \t\t\tkey name;
        \t\t}
        \t}
        \tclass Course extends Named
        \t{
        \t\tinvariant HasCapacity: capacity > 0;
        \t\tinvariant NotOverfull('Too many enrolments for ' + name): enrolments->size() <= capacity;
        \t\tattribute capacity : Integer = '30';
        \t\tattribute level : Level;
        \t\tattribute topics : String[*] { ordered, !unique };
        \t\tattribute credit : ecore::EDouble[?];
        \t\tproperty school#courses : School[?];
        \t\tproperty enrolments : Enrolment[*] { derived, readonly, transient, volatile }
        \t\t{
        \t\t\tderivation: school.students.enrolments->select(e | e.course = self);
        \t\t}
        \t\toperation isFull() : Boolean
        \t\t{
        \t\t\tbody: enrolments->size() >= capacity;
        \t\t}
        \t\toperation enrol(student : Student) : Enrolment[?]
        \t\t{
        \t\t\tprecondition Open: not isFull();
        \t\t\tprecondition: student <> null;
        \t\t\tpostcondition Recorded: enrolments->exists(e | e.student = student);
        \t\t}
        \t}
        \tclass Student extends Named
        \t{
        \t\tinvariant: enrolments->isUnique(course);
        \t\tattribute year : Integer
        \t\t{
        \t\t\tinitial: 1;
        \t\t}
        \t\tproperty enrolments : Enrolment[*] { composes };
        \t}
        \tclass Enrolment
        \t{
        \t\tannotation 'http://example.org/notes'(reviewed = 'yes');
        \t\tproperty course : Course;
        \t\tproperty student : Student { !resolve };
        \t\tattribute since : ecore::EDate[?];
        \t\tattribute active : Boolean[?];
        \t}
        }

        """

    /// A school metamodel with its constraints inline.
    static let inline = """
        package school : sch = 'http://example.org/school'
        {
        \tclass Course
        \t{
        \t\tinvariant HasCapacity: capacity > 0;
        \t\tinvariant NotOverfull('Too many enrolments for ' + name): enrolments->size() <= capacity;
        \t\tattribute name : String;
        \t\tattribute capacity : Integer;
        \t\tproperty enrolments : Enrolment[*] { composes };
        \t\tattribute load : Real { derived, readonly, transient, volatile }
        \t\t{
        \t\t\tderivation: enrolments->size() / capacity;
        \t\t}
        \t\tattribute rating : Integer
        \t\t{
        \t\t\tinitial: 0;
        \t\t}
        \t\toperation isFull() : Boolean
        \t\t{
        \t\t\tbody: enrolments->size() >= capacity;
        \t\t}
        \t\toperation enrol(student : Student) : Enrolment[?]
        \t\t{
        \t\t\tprecondition Open: not isFull();
        \t\t\tprecondition: student <> null;
        \t\t\tpostcondition Recorded: enrolments->exists(e | e.student = student);
        \t\t}
        \t}
        \tclass Student
        \t{
        \t\tinvariant: name <> '';
        \t\tattribute name : String;
        \t}
        \tclass Enrolment
        \t{
        \t\tproperty student : Student;
        \t}
        }

        """

    /// The same metamodel without constraints.
    static var bare: String {
        inline.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            !["invariant", "derivation:", "initial:", "body:", "precondition", "postcondition"].contains {
                line.trimmingCharacters(in: .whitespaces).hasPrefix($0)
            }
        }.joined(separator: "\n")
    }

    /// The constraints of the metamodel as a Complete OCL document.
    static let constraints = """
        import 'school.ecore'

        package school

        -- Invariants of courses
        context Course
        inv HasCapacity: capacity > 0
        inv NotOverfull('Too many enrolments for ' + name): enrolments->size() <= capacity

        context Course::load : Real
        derive: enrolments->size() / capacity

        context Course::rating : Integer
        init: 0

        context Course::isFull() : Boolean
        body: enrolments->size() >= capacity

        context Course::enrol(student : Student) : Enrolment
        pre Open: not isFull()
        pre: student <> null
        post Recorded: enrolments->exists(e | e.student = student)

        context Student
        inv: name <> ''

        endpackage
        """
}

/// Verifies that the invariants of OCLinEcore and Complete OCL documents evaluate through
/// their translation into AQL.
@Suite("Evaluation of translated OCL invariants")
struct OCLTranslationEvaluationTests {
    /// The school metamodel without constraints.
    ///
    /// - Returns: The packages of the metamodel.
    /// - Throws: An error if a package cannot be read.
    static func bare() throws -> [EPackage] {
        let result = OCLinEcoreReader.parse(OCLTranslationFixtures.bare)
        #expect(result.isValid, "\(result.diagnostics.map(\.message))")
        return result.packages
    }

    @Test("Invariants from an OCLinEcore model evaluate through the AQL translation")
    @MainActor
    func invariantsEvaluate() async throws {
        let package = try #require(OCLinEcoreReader.parse(OCLTranslationFixtures.school).packages.first)
        let course = try #require(package.getEClass("Course"))
        let invariants = OCLConstraintAnnotations.invariants(of: course)
        #expect(invariants.map(\.name) == ["HasCapacity", "NotOverfull"])
        var small = DynamicEObject(eClass: course)
        small.eSet("name", value: "Algebra")
        small.eSet("capacity", value: 0)
        var large = DynamicEObject(eClass: course)
        large.eSet("name", value: "Biology")
        large.eSet("capacity", value: 20)
        let resource = Resource()
        for object in [small, large] { _ = await resource.add(object) }
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "model")
        let context = AQLExecutionContext(executionEngine: engine, options: .standard)
        context.addResource(resource)
        let translation = OCLToAQLTranslator(packages: [package]).translate(invariants[0].expression)
        let aql = try #require(translation.aql)
        let expression = try #require(AQLParser().parse(aql).expression)
        var outcomes: [Bool] = []
        for object in [small, large] {
            context.setVariable(OCLSyntax.selfKeyword, value: object)
            outcomes.append(try await expression.evaluate(in: context) as? Bool ?? false)
        }
        #expect(outcomes == [false, true])
    }

    @Test("Applied invariants evaluate through the AQL translation")
    @MainActor
    func evaluation() async throws {
        let document = CompleteOCLReader.parse(OCLTranslationFixtures.constraints).document
        let package = try #require(CompleteOCLApplier.apply(document, to: try Self.bare()).packages.first)
        let course = try #require(package.getEClass("Course"))
        let enrolment = try #require(package.getEClass("Enrolment"))
        let student = try #require(package.getEClass("Student"))
        var alice = DynamicEObject(eClass: student)
        alice.eSet("name", value: "Alice")
        var nameless = DynamicEObject(eClass: student)
        nameless.eSet("name", value: "")
        var first = DynamicEObject(eClass: enrolment)
        first.eSet("student", value: alice.id)
        var second = DynamicEObject(eClass: enrolment)
        second.eSet("student", value: nameless.id)
        var full = DynamicEObject(eClass: course)
        full.eSet("name", value: "Chemistry")
        full.eSet("capacity", value: 1)
        full.eSet("enrolments", value: [first.id, second.id])
        let resource = Resource()
        for object in [full, first, second, alice, nameless] { _ = await resource.add(object) }
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "model")
        let context = AQLExecutionContext(executionEngine: engine, options: .standard)
        context.addResource(resource)
        let translator = OCLToAQLTranslator(packages: [package])
        func check(_ owner: EClass, _ object: DynamicEObject) async throws -> [Bool] {
            var outcomes: [Bool] = []
            for invariant in OCLConstraintAnnotations.invariants(of: owner) {
                let translation = translator.translate(invariant.expression)
                let aql = try #require(translation.aql)
                let expression = try #require(AQLParser().parse(aql).expression)
                context.setVariable(OCLSyntax.selfKeyword, value: object)
                outcomes.append(try await expression.evaluate(in: context) as? Bool ?? false)
            }
            return outcomes
        }
        #expect(try await check(course, full) == [true, false])
        #expect(try await check(student, alice) == [true])
        #expect(try await check(student, nameless) == [false])
    }
}
