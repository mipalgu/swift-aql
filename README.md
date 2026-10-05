# Swift AQL - Acceleo Query Language Library

[![CI](https://github.com/mipalgu/swift-aql/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-aql/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-aql/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-aql/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-aql%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-aql)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-aql%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-aql)

A pure Swift implementation of the Acceleo Query Language (AQL).

## Features

- **Pure Swift**: No Java/EMF dependencies, Swift 6.0+ with strict concurrency
- **Cross-Platform**: Full support for macOS 15.0+ and Linux
- **AQL Compatibility**: Implements core AQL concepts and syntax
- **EMF Integration**: Built on top of `swift-ecore` for seamless model querying
- **Performance**: Optimized for fast model navigation and querying

## Services

Operations on strings, collections, numbers, booleans and model objects are
provided as services. The standard library (Acceleo/AQL string, collection and
EObject services) is available in every `AQLExecutionContext`, and clients add
their own through `AQLServiceProvider`:

```swift
struct GreetingServices: AQLServiceProvider {
    var services: [AQLService] {
        [AQLService("greet", receiver: .string, arity: 1) { call in
            "\(try call.string(0)), \(try call.receiverString())"
        }]
    }
}

context.register(GreetingServices())
```

Calls `receiver.name(args)`, `receiver->name(args)` and `name(args)` search the
registered services (most recent first) and then the standard library. Services
may be asynchronous and use `call.context` to navigate the model. Iterator
arguments (`x | body`) arrive as `AQLLambda` values, and type arguments
(`ecore::EClass`) as `AQLTypeDescriptor` values.

## Parsing

`AQLParser().parse(_:)` reads one AQL expression from text and returns the expression, the diagnostics (`SourceDiagnostic` values with ranges and the codes of `AQLDiagnosticCode`) and the tokens. Host languages that embed AQL read their own tokens through an `AQLTokenCursor` and shape the nodes through an `AQLParserDelegate`. `AQLSyntax.tokens(in:)` splits text into highlighting tokens and never fails. Every expression node carries an `origin` (its range in the source text) that never takes part in equality, and `AQLTreePrinter` prints a tree as one deterministic line.

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-aql.git", branch: "main")
]
```

And add `"AQL"` to your target's dependencies.

## Building

```bash
# Build the library
swift build

# Run tests
swift test
```

## Licence

See the details in the LICENCE file.

## References

This implementation is based on the following standards and technologies:

- [Eclipse Acceleo](https://eclipse.dev/acceleo/) - The reference AQL implementation
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - The query language foundation
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
