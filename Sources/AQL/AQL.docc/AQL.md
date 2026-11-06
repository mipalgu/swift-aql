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

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingAQL>

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

## See Also

- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
