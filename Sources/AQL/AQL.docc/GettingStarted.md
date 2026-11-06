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
let resource = try await XMIParser().parse(URL(fileURLWithPath: "model.xmi"))

// Create an execution engine that knows the model
let engine = ECoreExecutionEngine(models: [:])
await engine.registerResource(resource, alias: "model")

// Create the AQL execution context with the default options
let context = AQLExecutionContext(executionEngine: engine, options: .standard)
context.addResource(resource)
```

The context is bound to the main actor, so the examples below run there.

Pass ``AQLOptions/legacy`` instead to evaluate expressions as version 0.6 did, or set
individual options of an ``AQLOptions`` value (see <doc:UnderstandingAQL#Options-and-Compatibility-with-0.6>).

## Parsing and Evaluating Queries

``AQLParser/parse(_:)`` never throws: it returns an ``AQLParseResult`` holding the
expression, if the text could be parsed, and the diagnostics. The examples below share
this helper, which turns the first diagnostic into an ``AQLSyntaxError``:

```swift
@MainActor
func evaluate(_ source: String, in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
    let parsed = AQLParser().parse(source)
    if let problem = parsed.diagnostics.first { throw AQLSyntaxError(problem) }
    guard let expression = parsed.expression else { return nil }
    return try await expression.evaluate(in: context)
}
```

The object a query starts from is the `self` variable.

### Simple Navigation

```swift
// Bind a model element as self
let element = await resource.getRootObjects()[0]
context.setVariable("self", value: element)

// Evaluate a simple navigation query
let name = try await evaluate("self.name", in: context)
print("Name: \(name as Any)")
```

### Collection Queries

```swift
// Get all attributes of an entity
let attributes = try await evaluate("self.attributes", in: context)

// Filter to required attributes only
let required = try await evaluate("self.attributes->select(a | a.isRequired)", in: context)

// Get attribute names
let names = try await evaluate("self.attributes->collect(a | a.name)", in: context)

// Count the attributes
let count = try await evaluate("self.attributes->size()", in: context)

// Get the length of each attribute name
let lengths = try await evaluate("self.attributes.name.size()", in: context)
```

The arrow calls a collection service, such as `size`, on the collection itself, while the dot
applies a call to each element of a collection, as it does when navigating `.name` (see
<doc:UnderstandingAQL#Dot-and-Arrow-Calls-on-Collections>).

### String Operations

```swift
// Uppercase
let upper = try await evaluate("self.name.toUpper()", in: context)

// Concatenation
let file = try await evaluate("self.name.concat('.swift')", in: context)

// Check prefix
let isGetter = try await evaluate("self.name.startsWith('get')", in: context)
```

## Using Variables

Register variables in the context for use in queries:

```swift
// Set a variable
context.setVariable("threshold", value: 10)

// Use in a query
let result = try await evaluate("self.attributes->select(a | a.length > threshold)", in: context)
```

## Conditional Expressions

```swift
let description = try await evaluate("""
    if self.isAbstract then
        'abstract class'
    else
        'concrete class'
    endif
    """, in: context)
```

## Let Expressions

Define local variables within expressions:

```swift
let result = try await evaluate("""
    let upper = self.name.toUpper() in
    upper.concat('_SUFFIX')
    """, in: context)
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

// Get the metaclass
"self.eClass()"
```

## Error Handling

Handle parsing and evaluation errors:

```swift
do {
    let result = try await evaluate("invalid query syntax", in: context)
} catch let error as AQLSyntaxError {
    print("Parse error: \(error)")
} catch let error as AQLExecutionError {
    print("Evaluation error: \(error)")
}
```

## Performance Tips

1. **Reuse parsed queries**: Parse once, evaluate many times
2. **Limit collection sizes**: Use `->first()` when you only need one result
3. **Short-circuit evaluation**: Place cheaper conditions first in filters

```swift
// Parse once
let parsed = AQLParser().parse("self.attributes->select(a | a.isRequired)")

// Evaluate multiple times
if let query = parsed.expression {
    for element in elements {
        context.setVariable("self", value: element)
        let result = try await query.evaluate(in: context)
    }
}
```

## Next Steps

- <doc:UnderstandingAQL> - Deep dive into AQL concepts
- ``AQLExpression`` - Expression API reference
- ``AQLExecutionContext`` - Context configuration
- ``AQLCollectionServices`` - Collection service reference
