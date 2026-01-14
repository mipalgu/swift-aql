# Swift AQL

The [swift-aql](https://github.com/mipalgu/swift-aql) package provides
a pure Swift implementation of the
[Acceleo Query Language (AQL)](https://eclipse.dev/acceleo/documentation/)
for model querying.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-aql.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux

## References

- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)

## Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit

## Documentation

The package provides model query and navigation capabilities.
For details, see [Getting Started](https://mipalgu.github.io/swift-aql/documentation/aql/gettingstarted) and [Understanding AQL](https://mipalgu.github.io/swift-aql/documentation/aql/understandingaql).
