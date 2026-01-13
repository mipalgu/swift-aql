# Getting Started with AQL

Learn how to add AQL to your project and write your first model queries.

## Overview

This guide walks you through adding AQL to your Swift project and demonstrates
how to write queries that navigate and filter model elements.

## Adding AQL to Your Project

Add swift-aql as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-aql.git", branch: "main"),
]
```

Then add the product dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "AQL", package: "swift-aql"),
    ]
)
```

## Setting Up the Execution Context

AQL queries execute within a context that provides access to models:

```swift
import AQL
import ECore

// Load your model
let xmiParser = XMIParser()
let resource = try await xmiParser.parse(URL(fileURLWithPath: "model.xmi"))

// Create an execution engine with your models
let engine = ECoreExecutionEngine(models: ["model": resource])

// Create the AQL execution context
let context = AQLExecutionContext(executionEngine: engine)
```

## Parsing and Evaluating Queries

### Simple Navigation

```swift
let parser = AQLParser()

// Parse a simple navigation query
let nameQuery = try parser.parse("self.name")

// Evaluate against a model element
let element = resource.rootObjects.first!
let name = try await nameQuery.evaluate(in: context, self: element)
print("Name: \(name)")
```

### Collection Queries

```swift
// Get all attributes of a class
let attrsQuery = try parser.parse("self.attributes")
let attributes = try await attrsQuery.evaluate(in: context, self: myClass)

// Filter to required attributes only
let requiredQuery = try parser.parse("self.attributes->select(a | a.isRequired)")
let required = try await requiredQuery.evaluate(in: context, self: myClass)

// Get attribute names
let namesQuery = try parser.parse("self.attributes->collect(a | a.name)")
let names = try await namesQuery.evaluate(in: context, self: myClass)
```

### String Operations

```swift
// Uppercase
let upperQuery = try parser.parse("self.name.toUpper()")

// Concatenation
let concatQuery = try parser.parse("self.name.concat('.swift')")

// Check prefix
let prefixQuery = try parser.parse("self.name.startsWith('get')")
```

## Using Variables

Register variables in the context for use in queries:

```swift
// Set a variable
context.setVariable("threshold", value: 10)

// Use in a query
let query = try parser.parse("self.attributes->select(a | a.length > threshold)")
let result = try await query.evaluate(in: context, self: myClass)
```

## Conditional Expressions

```swift
let conditionalQuery = try parser.parse("""
    if self.isAbstract then
        'abstract class'
    else
        'concrete class'
    endif
""")
let description = try await conditionalQuery.evaluate(in: context, self: myClass)
```

## Let Expressions

Define local variables within expressions:

```swift
let letQuery = try parser.parse("""
    let upper = self.name.toUpper() in
    upper.concat('_SUFFIX')
""")
let result = try await letQuery.evaluate(in: context, self: myClass)
```

## Common Query Patterns

### Finding Elements by Condition

```swift
// Find all public attributes
"self.attributes->select(a | a.visibility = 'public')"

// Find the first required attribute
"self.attributes->select(a | a.isRequired)->first()"

// Check if any attribute is an ID
"self.attributes->exists(a | a.isId)"
```

### Aggregation

```swift
// Count attributes
"self.attributes->size()"

// Check if all attributes have names
"self.attributes->forAll(a | a.name <> '')"

// Check if collection is empty
"self.attributes->isEmpty()"
```

### Type Operations

```swift
// Check type
"self.oclIsKindOf(Entity)"

// Cast to specific type
"self.oclAsType(Entity)"

// Get the type
"self.oclType()"
```

## Error Handling

Handle parsing and evaluation errors:

```swift
do {
    let query = try parser.parse("invalid query syntax")
    let result = try await query.evaluate(in: context, self: element)
} catch let error as AQLParseError {
    print("Parse error: \(error)")
} catch let error as AQLError {
    print("Evaluation error: \(error)")
}
```

## Performance Tips

1. **Reuse parsed queries**: Parse once, evaluate many times
2. **Limit collection sizes**: Use `->first()` when you only need one result
3. **Short-circuit evaluation**: Place cheaper conditions first in filters

```swift
// Parse once
let query = try parser.parse("self.attributes->select(a | a.isRequired)")

// Evaluate multiple times
for element in elements {
    let result = try await query.evaluate(in: context, self: element)
}
```

## Next Steps

- <doc:UnderstandingAQL> - Deep dive into AQL concepts
- ``AQLExpression`` - Expression API reference
- ``AQLExecutionContext`` - Context configuration
- ``AQLCollectionOperations`` - Collection operation reference
