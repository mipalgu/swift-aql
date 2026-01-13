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

// Create execution context
let engine = ECoreExecutionEngine(models: ["model": myModel])
let context = AQLExecutionContext(executionEngine: engine)

// Parse a query
let parser = AQLParser()
let query = try parser.parse("self.attributes->select(a | a.isRequired)")

// Evaluate against a model element
let result = try await query.evaluate(in: context, self: myClass)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingAQL>

### Execution

- ``AQLExecutionContext``
- ``AQLEvaluator``

### Expressions

- ``AQLExpression``
- ``AQLNavigationExpression``
- ``AQLOperationCallExpression``
- ``AQLCollectionExpression``
- ``AQLLiteralExpression``
- ``AQLVariableExpression``
- ``AQLLambdaExpression``
- ``AQLIfExpression``
- ``AQLLetExpression``

### Parsing

- ``AQLParser``
- ``AQLLexer``

### Operations

- ``AQLCollectionOperations``
- ``AQLStringOperations``
- ``AQLBooleanOperations``
- ``AQLNumericOperations``
- ``AQLTypeOperations``

### Errors

- ``AQLError``
- ``AQLParseError``

## See Also

- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
