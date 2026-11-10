//
//  AQLMultiLevelTests.swift
//  AQLMultiLevel
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import AQL
import ECore
import EMFBase
import Foundation
import MultiLevel
import Testing

@testable import AQLMultiLevel

/// Multi-level models for the AQL tests.
enum DeepFixtures {
    /// Product types, products and individual items over three levels.
    static let products = """
        Model Commerce@2 {
          Node ProductType {
            vat@1 : double = 7.5;
            price : double = 10.0;
            posPrice@2 : $self.price > 0$
          }
          someProducts@2 : $ProductType.allInstances()->size() >= 1$
        }

        Commerce BookStore {
          ProductType Book {
            vat = 4.0;
            pages : int;
          }
          ProductType Disc {
            vat = 10.0;
          }
        }

        BookStore Shop {
          Book patterns {
            price = 35.0;
            pages = 395;
          }
          Disc album {
            price = 20.0;
          }
          Book draft {}
        }
        """

    /// The arcade language with the constraints of the MetaDepth tutorial exercise, in AQL.
    static let arcade = """
        Model Arcade@2 {
          Node Tile@(2) {
            next : Tile[*];
            elements : ElementKind@0[*];
            noIsolated : $self.next->notEmpty() or Tile.allInstances()->exists(t | t.next->includes(self))$
          }
          abstract Node ElementKind {
            placed : $Tile.allInstances()->select(t | t.elements->includes(self))->size() = 1$
          }
          abstract Node CharacterKind : ElementKind {}
          Node HeroKind : CharacterKind {
            initLives@1 : int = 3;
            lives : int = 3;
          }
          Node EvilKind : CharacterKind {}
          Node TreasureKind : ElementKind {}
          someHero@2 : $HeroKind.allInstances()->size() >= 1$
          moreEvils@2 : $EvilKind.allInstances()->size() >= HeroKind.allInstances()->size()$
        }

        Arcade Maze {
          TreasureKind Coin {
            value : int = 10;
          }
          HeroKind Muncher {
            initLives = 5;
          }
          EvilKind Phantom {}
        }

        Maze Play {
          Tile t0 {
            next = [t1];
            elements = [c0, m];
          }
          Tile t1 {
            next = [t0];
            elements = [p];
          }
          Muncher m {}
          Phantom p {}
          Coin c0 {}
        }
        """

    /// Physical bicycles that refer to a catalogue model one level up.
    static let bicycles = """
        Model Cycling@2 {
          Node BicycleType {
            topSpeed@1 : double;
            serialNumber : String;
            alternative : BicycleType[0..1] {level=1};
          }
        }
        Cycling Catalogue {
          BicycleType Challenger {
            topSpeed = 70.0;
          }
          BicycleType Sprinter {
            topSpeed = 65.0;
          }
        }
        Catalogue Inventory {
          Challenger bike1 {
            serialNumber = "C-0001";
            alternative = Sprinter;
          }
        }
        """

    /// Reads a fixture that must have no errors.
    static func model(_ text: String) throws -> DeepModel {
        let result = MetaDepthReader.parse(text)
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.message))")
        return try #require(result.model)
    }
}

/// Evaluates AQL expressions against the deep views of a model.
@MainActor
struct DeepQuery {
    let model: DeepModel
    let views: [DeepLevelView]
    let context: AQLExecutionContext

    init(_ model: DeepModel, level: Int) async throws {
        self.model = model
        views = try await model.deepLevelViews(in: ResourceSet())
        let engine = ECoreExecutionEngine(models: [:])
        for view in views { await engine.registerResource(view.resource, alias: "L\(view.level)") }
        context = AQLExecutionContext(
            executionEngine: engine, options: .standard, serviceProviders: [AQLMultiLevelServices(views: views)])
        guard let view = views.first(where: { $0.level == level }) else { return }
        context.addResource(view.resource)
        for classifier in view.package.eClassifiers {
            context.setGlobalVariable(classifier.name, value: AQLTypeDescriptor(typeName: classifier.name))
        }
    }

    /// Evaluates an expression with `self` bound to the object of a clabject.
    func evaluate(_ text: String, on name: String? = nil) async throws -> (any EcoreValue)? {
        if let name, let clabject = model.clabject(named: name), let level = model.level(of: clabject.id),
            let view = views.first(where: { $0.level == level })
        {
            context.setVariable("self", value: await view.resource.resolve(clabject.id))
        }
        let parsed = AQLParser().parse(text)
        let expression = try #require(parsed.expression, "\(parsed.diagnostics.map(\.message))")
        return try await expression.evaluate(in: context)
    }

    /// The clabject names of a collection of view objects.
    func names(_ value: (any EcoreValue)?) -> [String] {
        AQLValues.coerceToCollection(value).compactMap { ($0 as? any EObject).flatMap { model.clabject($0.id)?.name } }
    }
}

/// Tests deep constraints written in AQL.
@Suite("AQL deep constraints")
struct AQLDeepConstraintTests {
    @Test("constraints hold on the deep instances at the level of their potency")
    func satisfied() async throws {
        let model = try DeepFixtures.model(DeepFixtures.products)
        #expect(await model.validate(evaluator: AQLDeepConstraintEvaluator()).isEmpty)
    }

    @Test("a violated constraint names its holder and the violating instance")
    func violated() async throws {
        let text = DeepFixtures.products.replacingOccurrences(of: "price = 20.0;", with: "price = 0.0;")
        let diagnostics = await (try DeepFixtures.model(text)).validate(evaluator: AQLDeepConstraintEvaluator())
        #expect(diagnostics.map(\.message) == ["constraint 'posPrice' of 'Commerce.ProductType' is violated on 'Shop.album'"])
    }

    @Test("the arcade exercise constraints hold, and a hero without a tile is reported")
    func arcade() async throws {
        let model = try DeepFixtures.model(DeepFixtures.arcade)
        #expect(await model.validate(evaluator: AQLDeepConstraintEvaluator()).isEmpty)
        let unplaced = DeepFixtures.arcade.replacingOccurrences(of: "elements = [c0, m];", with: "elements = [c0];")
        let diagnostics = await (try DeepFixtures.model(unplaced)).validate(evaluator: AQLDeepConstraintEvaluator())
        #expect(diagnostics.map(\.message) == ["constraint 'placed' of 'Arcade.ElementKind' is violated on 'Play.m'"])
        let crowd = DeepFixtures.arcade.replacingOccurrences(of: "Coin c0 {}", with: "Coin c0 {}\n  Muncher m2 {}")
        let crowded = await (try DeepFixtures.model(crowd)).validate(evaluator: AQLDeepConstraintEvaluator())
        #expect(crowded.map(\.message).contains("constraint 'moreEvils' of 'Arcade' is violated at level 0"))
    }

    @Test("bodies that are not AQL, such as EOL bodies, are reported and not reinterpreted")
    func notAQL() async throws {
        var model = try DeepFixtures.model(DeepFixtures.products)
        model.levels[0].constraints = [DeepConstraint(name: "eolStyle", potency: Potency(2), body: "ProductType.all.exists(p | p.price >)")]
        let diagnostics = await model.evaluateConstraints(evaluator: AQLDeepConstraintEvaluator())
        #expect(diagnostics.map(\.code) == [MultiLevelDiagnosticCode.constraintError])
        #expect(diagnostics.first?.message.contains("is not valid AQL (EOL bodies are not supported)") == true)
        model.levels[0].constraints = [DeepConstraint(name: "count", potency: Potency(2), body: "ProductType.allInstances()->size()")]
        let notBoolean = await model.evaluateConstraints(evaluator: AQLDeepConstraintEvaluator())
        #expect(notBoolean.first?.message.hasSuffix(AQLMultiLevelError.notBoolean("count").description) == true)
    }
}

/// Tests deep navigation, typing and the deep services through the views.
@Suite("AQL deep queries")
@MainActor
struct AQLDeepQueryTests {
    @Test("type tests and instance queries are deep through the view")
    func deepTyping() async throws {
        let query = try await DeepQuery(try DeepFixtures.model(DeepFixtures.products), level: 0)
        #expect(try await query.evaluate("self.oclIsKindOf(ProductType)", on: "patterns") as? Bool == true)
        #expect(try await query.evaluate("self.oclIsKindOf(Disc)", on: "patterns") as? Bool == false)
        #expect(query.names(try await query.evaluate("ProductType.allInstances()")).sorted() == ["album", "draft", "patterns"])
        #expect(query.names(try await query.evaluate("Book.allInstances()")).sorted() == ["draft", "patterns"])
    }

    @Test("slots, defaults and type-level slots are navigated like features")
    func navigation() async throws {
        let query = try await DeepQuery(try DeepFixtures.model(DeepFixtures.products), level: 0)
        #expect(try await query.evaluate("self.price", on: "patterns") as? Double == 35)
        #expect(try await query.evaluate("self.price", on: "draft") as? Double == 10)
        #expect(try await query.evaluate("self.vat", on: "draft") as? Double == 4)
        #expect(try await query.evaluate("self.vat * self.price", on: "album") as? Double == 200)
    }

    @Test("the deep services give linguistic and ontological information")
    func services() async throws {
        let query = try await DeepQuery(try DeepFixtures.model(DeepFixtures.products), level: 0)
        #expect(try await query.evaluate("self.ontologicalType().name", on: "patterns") as? String == "Book")
        #expect(try await query.evaluate("self.clabjectName()", on: "patterns") as? String == "patterns")
        #expect(try await query.evaluate("self.linguisticType()", on: "patterns") as? String == "Node")
        #expect(try await query.evaluate("self.level()", on: "patterns") as? Int == 0)
        #expect(try await query.evaluate("self.potency()", on: "patterns") as? Int == 0)
        #expect(try await query.evaluate("self.isDeepInstanceOf(ProductType)", on: "patterns") as? Bool == true)
        #expect(try await query.evaluate("self.isDeepInstanceOf(Disc)", on: "patterns") as? Bool == false)
        let deepTypes = AQLValues.coerceToCollection(try await query.evaluate("self.deepTypes()", on: "draft"))
        #expect(deepTypes.compactMap { ($0 as? EClass)?.name } == ["Book", "ProductType"])
        #expect(query.names(try await query.evaluate("ProductType.deepInstances()")).sorted() == [
            "Book", "Disc", "album", "draft", "patterns",
        ])
        #expect(query.names(try await query.evaluate("ProductType.instancesAtLevel(1)")) == ["Book", "Disc"])
        #expect(try await query.evaluate("self.typeAtLevel(1).vat", on: "patterns") as? Double == 4)
        #expect(try await query.evaluate("self.typeAtLevel(1).clabjectName()", on: "patterns") as? String == "Book")
        #expect(try await query.evaluate("self.slotValue('vat')", on: "patterns") as? Double == 4)
        #expect(try await query.evaluate("self.slotValue('pages')", on: "draft") == nil)
    }

    @Test("references to another level resolve through the views of that level")
    func crossLevelNavigation() async throws {
        var model = try DeepFixtures.model(DeepFixtures.bicycles)
        model.levelCrossing = .strict
        #expect(model.validateStructure().isEmpty)
        let query = try await DeepQuery(model, level: 0)
        #expect(try await query.evaluate("self.alternative.topSpeed", on: "bike1") as? Double == 65)
        #expect(try await query.evaluate("self.topSpeed", on: "bike1") as? Double == 70)
        #expect(try await query.evaluate("self.alternative.clabjectName()", on: "bike1") as? String == "Sprinter")
        #expect(try await query.evaluate("self.alternative.level()", on: "bike1") as? Int == 1)
    }

    @Test("the deep services leave other values to the standard library")
    func otherValues() async throws {
        let query = try await DeepQuery(try DeepFixtures.model(DeepFixtures.products), level: 0)
        await #expect(throws: (any Error).self) { try await query.evaluate("'text'.clabjectName()") }
        let services = AQLMultiLevelServices(views: [])
        #expect(services.clabject(of: "text") == nil)
        #expect(await services.deepInstances(of: AQLTypeDescriptor(typeName: "X"), atLevel: nil).values.isEmpty)
    }
}
