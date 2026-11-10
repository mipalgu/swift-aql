//
//  AQLIncrementalTests.swift
//  AQL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Synchronization
import Testing

@testable import AQL

/// A deterministic pseudo-random generator (SplitMix64), so that edit sequences repeat.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// A small company metamodel: a company contains departments, which contain people and
/// sub-departments; people have a name, an age and an optional mentor.
struct CompanyModel: Sendable {
    let company: EClass
    let department: EClass
    let person: EClass

    init() {
        let string = EDataType(name: "EString", instanceClassName: "String")
        let int = EDataType(name: "EInt", instanceClassName: "Int")
        var person = EClass(name: "Person")
        person.eStructuralFeatures = [
            EAttribute(name: "name", eType: string),
            EAttribute(name: "age", eType: int),
        ]
        person.eStructuralFeatures.append(EReference(name: "mentor", eType: person))
        var department = EClass(name: "Department")
        department.eStructuralFeatures = [
            EAttribute(name: "name", eType: string),
            EReference(name: "employees", eType: person, upperBound: -1, containment: true),
        ]
        department.eStructuralFeatures.append(
            EReference(name: "subDepartments", eType: department, upperBound: -1, containment: true))
        var company = EClass(name: "Company")
        company.eStructuralFeatures = [
            EAttribute(name: "name", eType: string),
            EReference(name: "departments", eType: department, upperBound: -1, containment: true),
        ]
        self.company = company
        self.department = department
        self.person = person
    }
}

/// A company with departments and people, in a resource registered with a context.
@MainActor
struct CompanyFixture {
    let model = CompanyModel()
    let resource: Resource
    let context: AQLExecutionContext
    let company: DynamicEObject
    var departments: [EUUID] = []

    init(departments departmentCount: Int = 3, people: Int = 4, seed: UInt64 = 1) async throws {
        resource = Resource(uri: "memory:/company.xmi")
        var company = DynamicEObject(eClass: model.company)
        company.eSet("name", value: "Example Pty Ltd")
        self.company = company
        await resource.add(company)
        var generator = SeededGenerator(seed: seed)
        var previous: EUUID?
        for d in 0..<departmentCount {
            var department = DynamicEObject(eClass: model.department)
            department.eSet("name", value: "D\(d)")
            try await resource.eAdd(objectId: company.id, feature: "departments", value: department)
            departments.append(department.id)
            for p in 0..<people {
                var person = DynamicEObject(eClass: model.person)
                person.eSet("name", value: "P\(d)-\(p)")
                person.eSet("age", value: Int.random(in: 18...65, using: &generator))
                if let previous, Bool.random(using: &generator) { person.eSet("mentor", value: previous) }
                try await resource.eAdd(objectId: department.id, feature: "employees", value: person)
                previous = person.id
            }
        }
        context = await Self.makeContext(for: resource)
    }

    /// A fresh context over a resource, as a batch evaluation would use.
    static func makeContext(for resource: Resource) async -> AQLExecutionContext {
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "company")
        let context = AQLExecutionContext(executionEngine: engine, options: .standard)
        context.addResource(resource)
        return context
    }

    /// Parses an expression.
    func parse(_ text: String) throws -> any AQLExpression {
        try #require(AQLParser().parse(text).expression)
    }

    /// The identifiers of all people in the resource.
    func people() async -> [EUUID] {
        await resource.getAllObjects().filter { $0.eClass.name == "Person" }.map(\.id)
    }
}

/// Collects the values reported to a handler.
@MainActor
final class ChangeLog {
    var changes: [AQLQueryChange] = []
}

@Suite("AQL incremental evaluation")
@MainActor
struct AQLIncrementalTests {

    // MARK: - Single expressions

    @Test("the first evaluation gives the value of an ordinary evaluation")
    func firstEvaluation() async throws {
        let f = try await CompanyFixture()
        let expression = try f.parse("company::Person.allInstances()->select(p | p.age >= 30)->collect(p | p.name)")
        let incremental = AQLIncrementalExpression(expression: expression, context: f.context)
        #expect(incremental.hasValue == false)
        #expect(incremental.dependencies.isUnbounded)
        let value = try await incremental.evaluate()
        let direct = try await expression.evaluate(in: CompanyFixture.makeContext(for: f.resource))
        #expect(AQLValues.description(of: value) == AQLValues.description(of: direct))
        #expect(incremental.dependencies.extents == ["Person"])
        #expect(incremental.dependencies.features.contains { $0.feature == "age" })
        #expect(incremental.dependencies.features.contains { $0.feature == "name" })
        #expect(incremental.evaluationCount == 1)
    }

    @Test("a change of a feature that was not read does not re-evaluate")
    func unaffectedChange() async throws {
        let f = try await CompanyFixture()
        let incremental = AQLIncrementalExpression(
            expression: try f.parse("company::Person.allInstances()->collect(p | p.age)"), context: f.context)
        try await incremental.evaluate()
        let person = try #require(await f.people().first)
        let changes = try await f.resource.eSetWithChanges(objectId: person, feature: "name", value: "Renamed")
        #expect(try await incremental.update(for: changes) == nil)
        #expect(incremental.evaluationCount == 1)
    }

    @Test("a change of a feature that was read re-evaluates and reports the difference")
    func affectedChange() async throws {
        let f = try await CompanyFixture()
        let incremental = AQLIncrementalExpression(
            expression: try f.parse("company::Person.allInstances()->select(p | p.age > 100)->collect(p | p.name)"),
            context: f.context)
        #expect(AQLValues.elements(of: try await incremental.evaluate())?.isEmpty == true)
        let person = try #require(await f.people().first)
        let changes = try await f.resource.eSetWithChanges(objectId: person, feature: "age", value: 120)
        let change = try #require(try await incremental.update(for: changes))
        #expect(change.isChanged)
        #expect(change.added.compactMap { $0 as? String } == ["P0-0"])
        #expect(change.removed.isEmpty)
        #expect(incremental.evaluationCount == 2)
    }

    @Test("creating and deleting instances re-evaluates extents")
    func extentChanges() async throws {
        var f = try await CompanyFixture()
        let incremental = AQLIncrementalExpression(
            expression: try f.parse("company::Person.allInstances()->size()"), context: f.context)
        #expect(try await incremental.evaluate() as? Int == 12)
        var newcomer = DynamicEObject(eClass: f.model.person)
        newcomer.eSet("name", value: "New")
        let created = try await f.resource.eAdd(objectId: f.departments[0], feature: "employees", value: newcomer)
        let change = try #require(try await incremental.update(for: created))
        #expect(change.newValue as? Int == 13)
        #expect(change.removed.compactMap { $0 as? Int } == [12])
        let deleted = await f.resource.delete([newcomer.id])
        #expect(try await incremental.update(for: deleted)?.newValue as? Int == 12)
        f.departments.removeAll()
        let renamed = try await f.resource.eSetWithChanges(objectId: f.company.id, feature: "name", value: "Other")
        #expect(try await incremental.update(for: renamed) == nil)
    }

    @Test("moving an object re-evaluates container queries")
    func containerChanges() async throws {
        let f = try await CompanyFixture()
        let people = await f.people()
        let person = try #require(people.first)
        let object = try #require(await f.resource.resolve(person))
        let incremental = AQLIncrementalExpression(
            expression: try f.parse("self.eContainer().name"), context: f.context, variables: ["self": object])
        #expect(try await incremental.evaluate() as? String == "D0")
        #expect(incremental.dependencies.containers.contains(person))
        let moved = try await f.resource.eAdd(objectId: f.departments[2], feature: "employees", value: person)
        #expect(try await incremental.update(for: moved)?.newValue as? String == "D2")
        let second = try #require(await f.resource.resolve(f.departments[1]))
        let siblings = AQLIncrementalExpression(
            expression: try f.parse("self.eContents()->size()"), context: f.context,
            variables: ["self": second])
        #expect(try await siblings.evaluate() as? Int == 4)
        let away = try await f.resource.eAdd(objectId: f.departments[0], feature: "employees", value: people[5])
        #expect(try await siblings.update(for: away)?.newValue as? Int == 3)
    }

    @Test("services registered by clients make the dependencies unbounded")
    func clientServices() async throws {
        struct Shout: AQLServiceProvider {
            var services: [AQLService] {
                [AQLService("shout", receiver: .string) { call in try call.receiverString().uppercased() }]
            }
        }
        let f = try await CompanyFixture()
        f.context.register(Shout())
        let incremental = AQLIncrementalExpression(expression: try f.parse("'a'.shout()"), context: f.context)
        #expect(try await incremental.evaluate() as? String == "A")
        #expect(incremental.dependencies.isUnbounded)
        let plain = AQLIncrementalExpression(expression: try f.parse("'a'.toUpper()"), context: f.context)
        #expect(try await plain.evaluate() as? String == "A")
        #expect(plain.dependencies.isEmpty)
    }

    @Test("reads through eGet, eAllContents, ancestors and eInverse are recorded")
    func reflectiveReads() async throws {
        let f = try await CompanyFixture()
        let department = try #require(await f.resource.resolve(f.departments[0]))
        let personID = try #require(await f.people().first)
        let person = try #require(await f.resource.resolve(personID))
        let get = AQLIncrementalExpression(
            expression: try f.parse("self.eGet('name')"), context: f.context, variables: ["self": department])
        #expect(try await get.evaluate() as? String == "D0")
        #expect(get.dependencies.features.contains(ModelFeatureKey(objectID: department.id, feature: "name")))
        let all = AQLIncrementalExpression(
            expression: try f.parse("self.eAllContents()->size()"), context: f.context, variables: ["self": department])
        #expect(try await all.evaluate() as? Int == 4)
        #expect(all.dependencies.objects.contains(department.id))
        let navigation = AQLIncrementalExpression(
            expression: try f.parse("self.eAllContents"), context: f.context, variables: ["self": department])
        _ = try await navigation.evaluate()
        #expect(navigation.dependencies.readsContainmentStructure)
        let ancestors = AQLIncrementalExpression(
            expression: try f.parse("self.ancestors()->size()"), context: f.context, variables: ["self": person])
        #expect(try await ancestors.evaluate() as? Int == 2)
        #expect(ancestors.dependencies.containers.contains(person.id))
        let inverse = AQLIncrementalExpression(
            expression: try f.parse("self.eInverse()->size()"), context: f.context, variables: ["self": person])
        _ = try await inverse.evaluate()
        #expect(inverse.dependencies.isUnbounded)
        let everything = AQLIncrementalExpression(
            expression: try f.parse("ecore::EObject.allInstances()->size()"), context: f.context)
        #expect(try await everything.evaluate() as? Int == 16)
        #expect(everything.dependencies.readsContainmentStructure)
        let implicit = AQLIncrementalExpression(
            expression: try f.parse("name"), context: f.context, variables: ["self": department])
        #expect(try await implicit.evaluate() as? String == "D0")
        #expect(implicit.dependencies.features.contains(ModelFeatureKey(objectID: department.id, feature: "name")))
        let container = AQLIncrementalExpression(
            expression: try f.parse("self.eContainer"), context: f.context, variables: ["self": person])
        _ = try await container.evaluate()
        #expect(container.dependencies.containers.contains(person.id))
        let contents = AQLIncrementalExpression(
            expression: try f.parse("self.eContents"), context: f.context, variables: ["self": department])
        _ = try await contents.evaluate()
        #expect(contents.dependencies.objects.contains(department.id))
    }

    @Test("a failed evaluation makes the next update evaluate again")
    func failedEvaluation() async throws {
        let f = try await CompanyFixture()
        let incremental = AQLIncrementalExpression(
            expression: try f.parse("undefinedVariable.name"), context: f.context)
        await #expect(throws: (any Error).self) { try await incremental.evaluate() }
        #expect(incremental.dependencies.isUnbounded)
        await #expect(throws: (any Error).self) { try await incremental.update(for: []) }
        #expect(incremental.evaluationCount == 2)
    }

    @Test("recordings nest and record nothing outside")
    func nestedRecording() async throws {
        let f = try await CompanyFixture()
        let department = try #require(await f.resource.resolve(f.departments[0]))
        #expect(f.context.isRecordingDependencies == false)
        let (outer, outerDependencies) = try await f.context.recordingDependencies {
            let (inner, innerDependencies) = try await f.context.recordingDependencies {
                try await f.context.navigate(from: department, property: "name")
            }
            #expect(innerDependencies.features.count == 1)
            #expect(f.context.isRecordingDependencies)
            return inner
        }
        #expect(outer as? String == "D0")
        #expect(outerDependencies.features.count == 1)
        await #expect(throws: (any Error).self) {
            _ = try await f.context.recordingDependencies {
                try await f.context.navigate(from: department, property: "missing")
            }
        }
        #expect(f.context.isRecordingDependencies == false)
    }

    // MARK: - Change descriptions

    @Test("query changes describe the difference of collections and single values")
    func changeDescriptions() {
        let same = AQLQueryChange(from: EcoreValueArray(["a", "b"]), to: EcoreValueArray(["a", "b"]))
        #expect(same.isChanged == false && same.added.isEmpty && same.removed.isEmpty)
        let reordered = AQLQueryChange(from: EcoreValueArray(["a", "b"]), to: EcoreValueArray(["b", "a"]))
        #expect(reordered.isChanged && reordered.added.isEmpty && reordered.removed.isEmpty)
        let grown = AQLQueryChange(from: EcoreValueArray(["a", "a"]), to: EcoreValueArray(["a", "a", "a", "c"]))
        #expect(grown.added.compactMap { $0 as? String } == ["a", "c"])
        let shrunk = AQLQueryChange(from: EcoreValueArray(["x", "a", "y"]), to: EcoreValueArray(["a"]))
        #expect(shrunk.removed.compactMap { $0 as? String } == ["x", "y"])
        let toSingle = AQLQueryChange(from: EcoreValueArray(["a"]), to: "a")
        #expect(toSingle.isChanged)
        let scalar = AQLQueryChange(from: 1, to: 2)
        #expect(scalar.added.compactMap { $0 as? Int } == [2] && scalar.removed.compactMap { $0 as? Int } == [1])
        let unchanged = AQLQueryChange(from: nil, to: nil)
        #expect(unchanged.isChanged == false)
        let fromNull = AQLQueryChange(from: nil, to: EcoreValueArray([]))
        #expect(fromNull.isChanged)
    }

    // MARK: - Observer

    @Test("an observer re-evaluates only the affected expressions")
    func observerRefresh() async throws {
        let f = try await CompanyFixture()
        let observer = AQLQueryObserver(context: f.context)
        #expect(observer.isObserving == false)
        await observer.start()
        await observer.start()
        #expect(observer.isObserving)
        let ages = AQLIncrementalExpression(
            expression: try f.parse("company::Person.allInstances()->collect(p | p.age)->size()"), context: f.context)
        let names = AQLIncrementalExpression(
            expression: try f.parse("company::Department.allInstances()->collect(d | d.name)"), context: f.context)
        let log = ChangeLog()
        let agesRegistration = try await observer.register(ages)
        let namesRegistration = try await observer.register(names) { log.changes.append($0) }
        #expect(observer.registrationCount == 2)
        #expect(observer.dependencyEntryCount == ages.dependencies.count + names.dependencies.count)
        #expect(observer.dependencyEntryCount > 2)
        #expect(observer.expression(for: namesRegistration) === names)

        try await f.resource.eSetWithChanges(objectId: f.departments[1], feature: "name", value: "Sales")
        #expect(observer.pendingChangeCount == 1)
        let updates = try await observer.refresh()
        #expect(updates.map(\.registration) == [namesRegistration])
        #expect(log.changes.count == 1)
        #expect(log.changes[0].added.compactMap { $0 as? String } == ["Sales"])
        #expect(ages.evaluationCount == 1)
        #expect(try await observer.refresh().isEmpty)

        #expect(observer.unregister(namesRegistration) === names)
        #expect(observer.unregister(namesRegistration) == nil)
        await observer.stop()
        #expect(observer.isObserving == false)
        try await f.resource.eSetWithChanges(objectId: f.departments[1], feature: "name", value: "Ignored")
        #expect(observer.pendingChangeCount == 0)
        let person = try #require(await f.people().first)
        let changes = await f.resource.delete([person])
        let external = try await observer.apply(changes)
        #expect(external.map(\.registration) == [agesRegistration])
        #expect(external.first?.change.newValue as? Int == 11)
    }

    @Test("an observer rejects expressions of another context and survives failures")
    func observerFailures() async throws {
        let f = try await CompanyFixture()
        let observer = AQLQueryObserver(context: f.context)
        let foreign = AQLIncrementalExpression(
            expression: try f.parse("1"), context: await CompanyFixture.makeContext(for: f.resource))
        await #expect(throws: AQLExecutionError.self) { try await observer.register(foreign) }
        let department = try #require(await f.resource.resolve(f.departments[0]))
        let fragile = AQLIncrementalExpression(
            expression: try f.parse("self.employees->first().name.size()"), context: f.context,
            variables: ["self": department])
        let later = AQLIncrementalExpression(
            expression: try f.parse("company::Person.allInstances()->size()"), context: f.context)
        try await observer.register(fragile)
        try await observer.register(later)
        var changes: [ResourceChange] = []
        for person in await f.resource.eGet(objectId: f.departments[0], feature: "employees") as? [EUUID] ?? [] {
            changes += await f.resource.delete([person])
        }
        await #expect(throws: (any Error).self) { try await observer.apply(changes) }
        #expect(later.dependencies.isUnbounded)
        var newcomer = DynamicEObject(eClass: f.model.person)
        newcomer.eSet("name", value: "Back")
        let added = try await f.resource.eAdd(objectId: f.departments[0], feature: "employees", value: newcomer)
        let updates = try await observer.apply(added)
        #expect(updates.count == 2)
        #expect(later.value as? Int == 9)
        #expect(try await observer.apply([]).isEmpty)
    }

    // MARK: - Differential testing

    /// The expressions checked by the differential test, with the variables they use.
    private static let differentialQueries: [(text: String, usesDepartment: Bool)] = [
        ("company::Person.allInstances()->select(p | p.age >= 40)->collect(p | p.name)", false),
        ("company::Person.allInstances()->size()", false),
        ("company::Department.allInstances()->collect(d | d.employees->size())", false),
        ("self.employees->collect(e | e.name)", true),
        ("company::Person.allInstances()->select(p | p.mentor <> null)->collect(p | p.mentor.name)", false),
        ("company::Person.allInstances()->collect(p | p.eContainer().name)", false),
        ("self.eAllContents(company::Person)->select(p | p.age < 30)->size()", true),
        ("company::Person.allInstances()->sortedBy(p | p.name)->collect(p | p.name)", false),
        ("company::Department.allInstances()->exists(d | d.employees->isEmpty())", false),
        ("self.ancestors()->size() + self.employees->size()", true),
    ]

    /// Applies a random edit to the company.
    private static func randomEdit(
        _ f: CompanyFixture, _ generator: inout SeededGenerator, counter: inout Int
    ) async throws -> [ResourceChange] {
        let people = await f.people()
        let departments = await f.resource.getAllObjects().filter { $0.eClass.name == "Department" }.map(\.id)
        switch Int.random(in: 0..<7, using: &generator) {
        case 0 where !people.isEmpty:
            return try await f.resource.eSetWithChanges(
                objectId: people.randomElement(using: &generator)!, feature: "age",
                value: Int.random(in: 18...65, using: &generator))
        case 1 where !people.isEmpty:
            counter += 1
            return try await f.resource.eSetWithChanges(
                objectId: people.randomElement(using: &generator)!, feature: "name", value: "R\(counter)")
        case 2:
            counter += 1
            var person = DynamicEObject(eClass: f.model.person)
            person.eSet("name", value: "N\(counter)")
            person.eSet("age", value: Int.random(in: 18...65, using: &generator))
            return try await f.resource.eAdd(
                objectId: departments.randomElement(using: &generator)!, feature: "employees", value: person)
        case 3 where people.count > 1:
            return await f.resource.delete([people.randomElement(using: &generator)!])
        case 4 where !people.isEmpty:
            return try await f.resource.eAdd(
                objectId: departments.randomElement(using: &generator)!, feature: "employees",
                value: people.randomElement(using: &generator)!)
        case 5 where people.count > 1:
            let person = people.randomElement(using: &generator)!
            let mentor = Bool.random(using: &generator) ? people.randomElement(using: &generator) : nil
            return try await f.resource.eSetWithChanges(objectId: person, feature: "mentor", value: mentor)
        default:
            counter += 1
            var sub = DynamicEObject(eClass: f.model.department)
            sub.eSet("name", value: "S\(counter)")
            return try await f.resource.eAdd(
                objectId: departments.randomElement(using: &generator)!, feature: "subDepartments", value: sub)
        }
    }

    @Test("incremental values equal fresh evaluations after random edits", arguments: [UInt64(7), 42, 2026])
    func differential(seed: UInt64) async throws {
        let f = try await CompanyFixture(departments: 3, people: 5, seed: seed)
        let department = try #require(await f.resource.resolve(f.departments[0]))
        let observer = AQLQueryObserver(context: f.context)
        await observer.start()
        var expressions: [AQLIncrementalExpression] = []
        for query in Self.differentialQueries {
            let expression = AQLIncrementalExpression(
                expression: try f.parse(query.text), context: f.context,
                variables: query.usesDepartment ? ["self": department] : [:])
            try await observer.register(expression)
            expressions.append(expression)
        }
        var generator = SeededGenerator(seed: seed)
        var counter = 0
        var reevaluations = 0
        let steps = 60
        for _ in 0..<steps {
            _ = try await Self.randomEdit(f, &generator, counter: &counter)
            reevaluations += try await observer.refresh().count
            let fresh = await CompanyFixture.makeContext(for: f.resource)
            let current = try #require(await f.resource.resolve(department.id))
            for (query, expression) in zip(Self.differentialQueries, expressions) {
                fresh.pushScope()
                if query.usesDepartment { fresh.setVariable("self", value: current) }
                let expected = try await expression.expression.evaluate(in: fresh)
                fresh.popScope()
                #expect(
                    AQLValues.description(of: expression.value) == AQLValues.description(of: expected),
                    "\(query.text) after seed \(seed)")
            }
        }
        #expect(reevaluations < steps * Self.differentialQueries.count)
    }
}
