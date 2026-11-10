//
//  OCLTranslationCorpusTests.swift
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

/// The environment that selects the reference corpus.
enum OCLTranslationCorpusEnvironment {
    /// The environment variable that names the corpus directory.
    static let variable = "OCL_REFERENCE_DIR"

    /// The corpus directory, if the variable is set.
    static var directory: String? { ProcessInfo.processInfo.environment[variable] }
}

/// Reads every OCLinEcore and Complete OCL document below the directory named by the
/// `OCL_REFERENCE_DIR` environment variable and reports how far each one is read, round-tripped,
/// applied and translated. The test is skipped when the variable is not set.
@Suite("OCL to AQL reference corpus", .enabled(if: OCLTranslationCorpusEnvironment.directory != nil))
struct OCLTranslationCorpusTests {
    /// The counts of translation outcomes.
    struct Coverage {
        var complete = 0
        var withNotes = 0
        var untranslatable = 0
        var syntaxErrors = 0
        var reasons: [String: Int] = [:]

        mutating func add(_ expression: String, translator: OCLToAQLTranslator) {
            let translation = translator.translate(expression)
            if translation.diagnostics.contains(where: { $0.code != OCLDiagnosticCode.untranslatable && $0.code != OCLDiagnosticCode.semanticGap }) {
                syntaxErrors += 1
            } else if translation.aql == nil {
                untranslatable += 1
                for diagnostic in translation.diagnostics where diagnostic.code == OCLDiagnosticCode.untranslatable {
                    reasons[diagnostic.message, default: 0] += 1
                }
            } else if translation.diagnostics.isEmpty {
                complete += 1
            } else {
                withNotes += 1
            }
        }

        var summary: String {
            "translated \(complete), translated with notes \(withNotes), untranslatable \(untranslatable), unparsable \(syntaxErrors)"
        }
    }

    /// The files below a directory with one of the extensions, sorted.
    static func files(below directory: URL, extension pathExtension: String) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isFile, url.pathExtension == pathExtension { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }

    /// Every OCL expression stored in packages.
    static func expressions(in packages: [EPackage]) -> [String] {
        var result: [String] = []
        func visit(_ package: EPackage) {
            for classifier in package.eClassifiers {
                if let eClass = classifier as? EClass {
                    result += OCLConstraintAnnotations.invariants(of: eClass).map(\.expression)
                    for operation in eClass.eOperations {
                        result += OCLConstraintAnnotations.preconditions(of: operation).map(\.expression)
                        result += OCLConstraintAnnotations.postconditions(of: operation).map(\.expression)
                        if let body = OCLConstraintAnnotations.body(of: operation) { result.append(body) }
                    }
                    for feature in eClass.eStructuralFeatures {
                        if let attribute = feature as? EAttribute {
                            result += [OCLConstraintAnnotations.initial(of: attribute), OCLConstraintAnnotations.derivation(of: attribute)].compactMap { $0 }
                        }
                        if let reference = feature as? EReference {
                            result += [OCLConstraintAnnotations.initial(of: reference), OCLConstraintAnnotations.derivation(of: reference)].compactMap { $0 }
                        }
                    }
                } else if let dataType = classifier as? EDataType {
                    result += OCLConstraintAnnotations.invariants(of: dataType).map(\.expression)
                } else if let eEnum = classifier as? EEnum {
                    result += OCLConstraintAnnotations.invariants(of: eEnum).map(\.expression)
                }
            }
            package.eSubpackages.forEach(visit)
        }
        packages.forEach(visit)
        return result
    }

    /// The directory of the corpus.
    static var directory: URL { URL(fileURLWithPath: OCLTranslationCorpusEnvironment.directory ?? "") }

    /// Shortens a path to its location within the corpus.
    static func relative(_ url: URL) -> String {
        String(url.path.dropFirst(directory.path.count))
    }

    @Test("OCLinEcore documents are read, round-tripped and translated")
    func oclinecore() throws {
        var coverage = Coverage()
        var valid = 0
        var roundTrips = 0
        let files = Self.files(below: Self.directory, extension: OCLinEcoreSyntax.fileExtension)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = OCLinEcoreReader.parse(text, sourceName: url.lastPathComponent)
            let errors = result.diagnostics.filter { $0.severity == .error }
            if errors.isEmpty { valid += 1 }
            let written = OCLinEcoreWriter.write(result.packages)
            let reread = OCLinEcoreReader.parse(written.text)
            let same = OCLMetamodelSummary.describe(reread.packages) == OCLMetamodelSummary.describe(result.packages)
            if same && reread.isValid { roundTrips += 1 }
            let translator = OCLToAQLTranslator(packages: result.packages)
            var local = Coverage()
            for expression in Self.expressions(in: result.packages) {
                coverage.add(expression, translator: translator)
                local.add(expression, translator: translator)
            }
            let firstError = errors.first.map { " first error \($0.range?.start.line ?? 0):\($0.range?.start.column ?? 0) \($0.message)" } ?? ""
            print("CORPUS oclinecore \(Self.relative(url)): errors \(errors.count), round trip \(same && reread.isValid ? "same" : "differs"), \(local.summary)\(firstError)")
        }
        print("CORPUS oclinecore total: \(files.count) files, \(valid) without errors, \(roundTrips) round-tripped; \(coverage.summary)")
        for (reason, count) in coverage.reasons.sorted(by: { $0.value > $1.value }) { print("CORPUS oclinecore untranslatable \(count)x \(reason)") }
        #expect(files.count > 0)
    }

    @Test("Complete OCL documents are read, applied and translated")
    func completeOCL() async throws {
        var coverage = Coverage()
        var valid = 0
        var applied = 0
        let files = Self.files(below: Self.directory, extension: CompleteOCLSyntax.fileExtension)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = CompleteOCLReader.parse(text, sourceName: url.lastPathComponent)
            let errors = result.diagnostics.filter { $0.severity == .error }
            if errors.isEmpty { valid += 1 }
            var packages: [EPackage] = []
            let folder = url.deletingLastPathComponent()
            var candidates = [url.deletingPathExtension().appendingPathExtension("ecore")]
            for anImport in result.document.imports {
                if OCLTypeResolver.isEcoreURI(anImport.target) { packages.append(EcorePackage.instance) }
                let name = URL(fileURLWithPath: anImport.target).lastPathComponent
                if name.hasSuffix(".ecore") { candidates.append(folder.appendingPathComponent(name)) }
            }
            for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
                if let package = try? await EPackage(url: candidate), !packages.contains(where: { $0.nsURI == package.nsURI }) {
                    packages.append(package)
                }
            }
            var application = ""
            if !packages.isEmpty {
                let outcome = CompleteOCLApplier.apply(result.document, to: packages, sourceName: url.lastPathComponent)
                let unresolved = outcome.diagnostics.filter { $0.severity == .error }
                if unresolved.isEmpty { applied += 1 }
                application = ", applied to \(packages.map(\.name)) with \(outcome.appliedCount) specifications and \(unresolved.count) unresolved"
                    + (unresolved.first.map { " (first: \($0.message))" } ?? "")
            }
            let translator = OCLToAQLTranslator(packages: packages)
            var local = Coverage()
            for (_, constraint) in result.document.allConstraints {
                coverage.add(constraint.expression, translator: translator)
                local.add(constraint.expression, translator: translator)
            }
            let firstError = errors.first.map { " first error \($0.range?.start.line ?? 0):\($0.range?.start.column ?? 0) \($0.message)" } ?? ""
            print("CORPUS ocl \(Self.relative(url)): errors \(errors.count), contexts \(result.document.classifierContexts.count + result.document.operationContexts.count + result.document.propertyContexts.count)\(application), \(local.summary)\(firstError)")
        }
        print("CORPUS ocl total: \(files.count) files, \(valid) without errors, \(applied) applied without unresolved contexts; \(coverage.summary)")
        for (reason, count) in coverage.reasons.sorted(by: { $0.value > $1.value }) { print("CORPUS ocl untranslatable \(count)x \(reason)") }
        #expect(files.count > 0)
    }

    /// The corpus metamodel, constraints and instance model that are evaluated end to end.
    static let evaluationFiles = (
        metamodel: "tests/org.eclipse.ocl.examples.xtext.tests/models/ecore/RoyalAndLoyal.ecore",
        constraints: "tests/org.eclipse.ocl.examples.xtext.tests/models/ecore/RoyalAndLoyal.ocl",
        model: "tests/org.eclipse.ocl.examples.xtext.tests/models/ecore/RoyalAndLoyal.xmi"
    )

    @Test("Translated invariants evaluate on a corpus instance model")
    @MainActor
    func evaluation() async throws {
        let metamodelURL = Self.directory.appendingPathComponent(Self.evaluationFiles.metamodel)
        let constraintsURL = Self.directory.appendingPathComponent(Self.evaluationFiles.constraints)
        let modelURL = Self.directory.appendingPathComponent(Self.evaluationFiles.model)
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return }
        let document = CompleteOCLReader.parse(try String(contentsOf: constraintsURL, encoding: .utf8)).document
        let metamodel = try await EPackage(url: metamodelURL)
        let applied = CompleteOCLApplier.apply(document, to: [metamodel])
        let package = try #require(applied.packages.first)
        let resourceSet = ResourceSet()
        let loaded = try await ModelIO.load(url: modelURL, resourceSet: resourceSet, metamodels: [metamodelURL])
        let objects = await loaded.resource.getAllObjects()
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(loaded.resource, alias: "model")
        let context = AQLExecutionContext(executionEngine: engine, options: .standard)
        context.addResource(loaded.resource)
        let translator = OCLToAQLTranslator(packages: [package])
        var parsed: [String: (any AQLExpression)?] = [:]
        var outcomes: [String: Int] = [:]
        var failures: [String: Int] = [:]
        for object in objects {
            guard let eClass = package.getEClass(object.eClass.name) else { continue }
            let owners = eClass.eAllSuperTypes.compactMap { package.getEClass($0.name) } + [eClass]
            for owner in owners {
                for invariant in OCLConstraintAnnotations.invariants(of: owner) {
                    let key = owner.name + "." + (invariant.name ?? "")
                    if parsed[key] == nil {
                        parsed[key] = translator.translate(invariant.expression).aql.flatMap { AQLParser().parse($0).expression }
                    }
                    guard let expression = parsed[key] ?? nil else {
                        outcomes["untranslated", default: 0] += 1
                        continue
                    }
                    context.setVariable(OCLSyntax.selfKeyword, value: object)
                    do {
                        let value = try await expression.evaluate(in: context)
                        outcomes[(value as? Bool).map { $0 ? "satisfied" : "violated" } ?? "not Boolean", default: 0] += 1
                        if ProcessInfo.processInfo.environment["OCL_CORPUS_VERBOSE"] != nil { print("CORPUS detail \(key) => \(AQLValues.description(of: value)) :: \(invariant.expression.prefix(100))") }
                    } catch {
                        outcomes["failed", default: 0] += 1
                        failures[key + ": " + String(describing: error).prefix(120), default: 0] += 1
                    }
                }
            }
        }
        print("CORPUS evaluation \(objects.count) objects: " + outcomes.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        for (failure, count) in failures.sorted(by: { $0.value > $1.value }) { print("CORPUS evaluation failure \(count)x \(failure)") }
        #expect(outcomes["satisfied", default: 0] > 0)
    }
}
