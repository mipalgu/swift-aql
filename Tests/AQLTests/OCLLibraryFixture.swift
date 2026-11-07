//
//  OCLOCLLibraryFixture.swift
//  AQLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OCL

@testable import AQL

/// A small, self-authored library model for evaluating translated expressions.
///
/// The metamodel `lib` has an enumeration `Genre` (`fiction`, `science`), a class `Book`
/// (`title`, `copies`, `genre`, `tags`) and a class `Library` (`name`, `books`). The model has
/// one library `City` with the books `Alpha` (2 copies, fiction, tags `x`, `y`) and `Beta`
/// (3 copies, science, tag `y`).
@MainActor
struct OCLLibraryFixture {
    /// The metamodel.
    let package: EPackage

    /// The library object.
    let library: DynamicEObject

    /// The book objects, in order.
    let books: [DynamicEObject]

    /// The resource that holds the objects.
    let resource: Resource

    /// The resource that holds the metamodel.
    let metamodel: Resource

    /// Creates the fixture.
    init() async {
        let genre = EEnum(name: "Genre", literals: [EEnumLiteral(name: "fiction", value: 0), EEnumLiteral(name: "science", value: 1)])
        let string = EcorePackage.classifier(named: "EString")!
        let integer = EcorePackage.classifier(named: "EInt")!
        var book = EClass(name: "Book")
        book.eStructuralFeatures = [
            EAttribute(name: "title", eType: string), EAttribute(name: "copies", eType: integer),
            EAttribute(name: "genre", eType: genre), EAttribute(name: "tags", eType: string, upperBound: -1),
        ]
        var library = EClass(name: "Library")
        library.eStructuralFeatures = [
            EAttribute(name: "name", eType: string),
            EReference(name: "books", eType: book, upperBound: -1, containment: true),
        ]
        var package = EPackage(name: "lib", nsURI: "http://example.org/lib", nsPrefix: "lib")
        package.eClassifiers = [genre, book, library]
        var alpha = DynamicEObject(eClass: book)
        alpha.eSet("title", value: "Alpha")
        alpha.eSet("copies", value: 2)
        alpha.eSet("genre", value: "fiction")
        alpha.eSet("tags", value: EcoreValueArray(["x", "y"]))
        var beta = DynamicEObject(eClass: book)
        beta.eSet("title", value: "Beta")
        beta.eSet("copies", value: 3)
        beta.eSet("genre", value: "science")
        beta.eSet("tags", value: EcoreValueArray(["y"]))
        var city = DynamicEObject(eClass: library)
        city.eSet("name", value: "City")
        city.eSet("books", value: [alpha.id, beta.id])
        let resource = Resource()
        for object in [city, alpha, beta] { _ = await resource.add(object) }
        let metamodel = Resource()
        _ = await metamodel.add(package)
        self.package = package
        self.library = city
        self.books = [alpha, beta]
        self.resource = resource
        self.metamodel = metamodel
    }

    /// Creates an evaluation context for the model with the standard AQL options.
    func makeContext() async -> AQLExecutionContext {
        let engine = ECoreExecutionEngine(models: [:])
        await engine.registerResource(resource, alias: "model")
        let context = AQLExecutionContext(executionEngine: engine, options: .standard)
        context.addResource(resource)
        context.addResource(metamodel)
        return context
    }

    /// Translates an OCL expression and evaluates it for an object.
    ///
    /// - Parameters:
    ///   - ocl: The OCL expression.
    ///   - object: The context object, by default the library.
    /// - Returns: The value of the translated expression.
    func evaluate(_ ocl: String, for object: DynamicEObject? = nil) async throws -> (any EcoreValue)? {
        let translation = OCLToAQLTranslator(packages: [package]).translate(ocl)
        guard let aql = translation.aql else { throw OCLTranslationFailure(diagnostics: translation.diagnostics) }
        let parsed = AQLParser().parse(aql)
        guard let expression = parsed.expression else { throw OCLTranslationFailure(diagnostics: parsed.diagnostics) }
        let context = await makeContext()
        context.setVariable(OCLSyntax.selfKeyword, value: object ?? library)
        return try await expression.evaluate(in: context)
    }
}

/// The error thrown when an expression cannot be translated or the translation cannot be parsed.
struct OCLTranslationFailure: Error, CustomStringConvertible {
    /// The diagnostics of the failure.
    let diagnostics: [SourceDiagnostic]

    /// The messages of the diagnostics.
    var description: String { diagnostics.map(\.message).joined(separator: "; ") }
}
