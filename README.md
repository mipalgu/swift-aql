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

The documentation is published at <https://mipalgu.github.io/swift-aql/>. The DocC
catalogue covers getting started, the language, services, options and compatibility with
version 0.6 (`AQLOptions.legacy`), containment queries, parsing and unset features. Build
it with the `docc` tooling or read it online: the
[AQL](https://mipalgu.github.io/swift-aql/documentation/aql/) and
[AQLMultiLevel](https://mipalgu.github.io/swift-aql/documentation/aqlmultilevel/) module
pages list the whole API.

The `swift-aql` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/)
is described in [swift-aql](https://mipalgu.github.io/swift-modelling/documentation/swift_aql/index.html),
and the AQL tutorials introduce it step by step:

- [AQL Basics](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-01-basics/index.html)
- [Filtering and Selection](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-02-filtering-selection/index.html)
- [Collection Operations](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-03-collection-operations/index.html)
- [AQL in MTL Templates](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-04-aql-in-mtl/index.html)
- [Complex Queries](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-05-complex-queries/index.html)
- [Querying Models with AQL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/06-querying-models/index.html)
- [Multi-Level Modelling with Potency](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/multilevel-01-deep-modelling/index.html)
- [Reusing Modules with Model Typing](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/typing-01-check-compat/index.html)

See all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html).

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Licence

See the details in the LICENCE file.

## References

This implementation is based on the following standards and technologies:

- [Eclipse Acceleo](https://eclipse.dev/acceleo/) - The reference AQL implementation
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - The query language foundation
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
