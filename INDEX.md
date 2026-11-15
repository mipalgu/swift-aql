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

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Documentation

The package provides model query and navigation capabilities. For details, see
[Getting Started](documentation/aql/gettingstarted) and
[Understanding AQL](documentation/aql/understandingaql). The
[AQL](documentation/aql/) and
[AQLMultiLevel](documentation/aqlmultilevel/) module pages list the whole API.

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
