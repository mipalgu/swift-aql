# Swift AQL - Acceleo Query Language Library

[![CI](https://github.com/mipalgu/swift-aql/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-aql/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-aql/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-aql/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-aql%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-aql)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-aql%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-aql)

A pure Swift implementation of the Acceleo Query Language (AQL).

## Features

- **Pure Swift**: No Java/EMF dependencies, Swift 6.0+ with strict concurrency
- **Cross-Platform**: Full support for macOS 15.0+ and Linux
- **AQL Compatibility**: Conforms to Eclipse AQL by default, with options to emulate earlier behaviour
- **EMF Integration**: Built on top of `swift-ecore` for seamless model querying
- **Extensible**: Clients add their own services through `AQLServiceProvider`
- **Incremental queries**: re-evaluated only when a model change affects what they read
- **Multi-level models**: deep constraints and services through the `AQLMultiLevel` library
- **OCL translation**: OCL constraints translated into AQL by `OCLToAQLTranslator`
- **Performance**: Optimized for fast model navigation and querying

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

And add `"AQL"` to your target's dependencies, and `"AQLMultiLevel"` for multi-level models.

## Usage

```swift
import AQL

let context = AQLExecutionContext(options: .standard)
let parsed = AQLParser().parse("Sequence{'a', 'b'} + Sequence{'b', 'c'}")
if let expression = parsed.expression {
    let result = try await expression.evaluate(in: context)
    // Sequence{'a', 'b', 'b', 'c'}
}
```

Pass `.legacy` instead of `.standard` to evaluate as version 0.6 did, or set
individual `AQLOptions` such as `sequenceUnion`, `nullAddition`, `textForm` and
`strict`.

## Building

```bash
# Build the library
swift build

# Run tests
swift test
```

## Documentation

The DocC catalogue covers getting started, the language, services, options and
compatibility with version 0.6 (`AQLOptions.legacy`), containment queries, parsing and
unset features. Build it with the `docc` tooling or read it online through the
[Swift Package Index](https://swiftpackageindex.com/mipalgu/swift-aql).

## Licence

See the details in the LICENCE file.

## References

This implementation is based on the following standards and technologies:

- [Eclipse Acceleo](https://eclipse.dev/acceleo/) - The reference AQL implementation
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - The query language foundation
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
