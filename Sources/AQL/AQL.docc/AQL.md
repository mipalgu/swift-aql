# ``AQL``

@Metadata {
    @DisplayName("AQL")
}

A pure Swift implementation of the [Acceleo Query Language (AQL)](https://eclipse.dev/acceleo/documentation/) for model querying.

## Overview

AQL provides a powerful expression language for querying and navigating ECore models.
It supports navigation, collection operations, string manipulation, and type operations,
making it ideal for model-driven engineering tasks.

This implementation follows the [Acceleo Query Language specification](https://eclipse.dev/acceleo/documentation/)
and is based on [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) semantics,
whilst providing a type-safe Swift API for integration with the ECore metamodelling framework.

### Key Features

- **Model navigation**: Traverse models using intuitive dot notation
- **Collection operations**: Filter, map, and aggregate collections
- **String operations**: Comprehensive string manipulation
- **Type operations**: Type checking, casting, and reflection
- **Boolean logic**: Full support for logical expressions
- **Conditionals**: If-then-else expressions
- **Incremental queries**: Values kept up to date as the models change, re-evaluating only
  the expressions that a change affects; see <doc:IncrementalQueries>

### Quick Example

```swift
import AQL
import ECore

// Create an execution context with the default options
let engine = ECoreExecutionEngine(models: [:])
await engine.registerResource(myResource, alias: "model")
let context = AQLExecutionContext(executionEngine: engine, options: .standard)
context.addResource(myResource)
context.setVariable("self", value: element)

// Parse a query and evaluate it
let parsed = AQLParser().parse("self.attributes->select(a | a.isRequired)")
if let query = parsed.expression {
    let result = try await query.evaluate(in: context)
}
```

## Related Documentation

- [swift-aql command-line tool](https://mipalgu.github.io/swift-modelling/documentation/swift_aql/index.html) - the `swift-aql` tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/)

### Tutorials

- [AQL Basics](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-01-basics/index.html)
- [Filtering and Selection](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-02-filtering-selection/index.html)
- [Collection Operations](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-03-collection-operations/index.html)
- [AQL in MTL Templates](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-04-aql-in-mtl/index.html)
- [Complex Queries](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-05-complex-queries/index.html)
- [Querying Models with AQL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/06-querying-models/index.html)
- [Multi-Level Modelling with Potency](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/multilevel-01-deep-modelling/index.html)
- [Reusing Modules with Model Typing](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/typing-01-check-compat/index.html)
- [All tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)

### Related Packages

- [ECore](https://mipalgu.github.io/swift-ecore/documentation/ecore/) and [OCL](https://mipalgu.github.io/swift-ecore/documentation/ocl/) in [swift-ecore](https://mipalgu.github.io/swift-ecore/) - the metamodelling framework that AQL queries
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL templates evaluate AQL expressions
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL transformations use AQL for their expressions
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - command-line tools, code generators and tutorials
- [AQLMultiLevel](https://mipalgu.github.io/swift-aql/documentation/aqlmultilevel/) - AQL for multi-level models

### Standards

- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingAQL>
- <doc:IncrementalQueries>

### Execution

- ``AQLExecutionContext``

### Options

- ``AQLOptions``
- ``AQLCollectionArguments``
- ``AQLCollectionKinds``
- ``AQLSingleValueCollections``
- ``AQLContainerLookup``
- ``AQLSequenceUnion``
- ``AQLNullAddition``
- ``AQLTextForm``

### Expressions

- ``AQLExpression``
- ``AQLNavigationExpression``
- ``AQLCallExpression``
- ``AQLCollectionExpression``
- ``AQLCollectionLiteralExpression``
- ``AQLLiteralExpression``
- ``AQLVariableExpression``
- ``AQLLambdaExpression``
- ``AQLConditionalExpression``
- ``AQLLetExpression``
- ``AQLBinaryExpression``
- ``AQLUnaryExpression``

### Parsing

- ``AQLParser``
- ``AQLParseResult``
- ``AQLTokenCursor``
- ``AQLParserDelegate``
- ``AQLSyntax``
- ``AQLTreePrinter``
- ``AQLDiagnosticCode``

### Translation from OCL

- ``OCLToAQLTranslator``
- ``OCLToAQLTranslation``

### Services

- ``AQLService``
- ``AQLServiceCall``
- ``AQLServiceProvider``
- ``AQLStandardLibrary``
- ``AQLCollectionServices``
- ``AQLStringServices``
- ``AQLBooleanServices``
- ``AQLNumberServices``
- ``AQLObjectServices``

### Errors

- ``AQLSyntaxError``
- ``AQLExecutionError``
