# Swift AQL - Acceleo Query Language

The [swift-aql](https://github.com/mipalgu/swift-aql) package provides a pure Swift
implementation of the [Acceleo Query Language (AQL)](https://eclipse.dev/acceleo/documentation/)
for model querying.

## Overview

Swift AQL enables powerful model queries in Swift, providing:

- **AQL expression support**: Parse and evaluate AQL query expressions
- **Navigation**: Traverse model structures using dot notation
- **Collections**: Rich collection operations (select, collect, reject, etc.)
- **Type operations**: Type checking, casting, and reflection
- **String operations**: Comprehensive string manipulation
- **OCL compatibility**: Based on [Object Constraint Language (OCL)](https://www.omg.org/spec/OCL/) semantics

## Installation

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

## Quick Start

```swift
import AQL
import ECore

// Create execution context
let engine = ECoreExecutionEngine(models: ["model": myModel])
let context = AQLExecutionContext(executionEngine: engine)

// Parse and evaluate a query
let parser = AQLParser()
let expression = try parser.parse("self.attributes->select(a | a.isRequired)->size()")

// Evaluate with a context object
let result = try await expression.evaluate(in: context, self: myClass)
print("Required attributes: \(result)")
```

## AQL Syntax Examples

```aql
-- Navigation
self.name
self.package.name
self.attributes

-- Collection operations
self.attributes->size()
self.attributes->first()
self.attributes->select(a | a.visibility = 'public')
self.attributes->collect(a | a.name)
self.attributes->forAll(a | a.name <> '')

-- String operations
self.name.toUpper()
self.name.concat('.swift')
self.name.startsWith('get')

-- Conditionals
if self.isAbstract then 'abstract' else 'concrete' endif
```

## Documentation

Detailed documentation is available in the generated DocC documentation:

- **Getting Started**: Installation and first query
- **Understanding AQL**: Expressions, navigation, and operations
- **API Reference**: Complete API documentation

## Requirements

- macOS 15.0+
- Swift 6.0+
- swift-ecore

## References

This implementation is based on the following standards and technologies:

- [Eclipse Acceleo](https://eclipse.dev/acceleo/) - The reference AQL implementation
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - The query language foundation
- [Eclipse EMF (Modeling Framework)](https://eclipse.dev/emf/) - The metamodelling foundation

## Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit
