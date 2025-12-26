# Swift AQL - Acceleo Query Language Library

A pure Swift implementation of the Acceleo Query Language (AQL).

## Features

- **Pure Swift**: No Java/EMF dependencies, Swift 6.0+ with strict concurrency
- **Cross-Platform**: Full support for macOS 15.0+ and Linux
- **AQL Compatibility**: Implements core AQL concepts and syntax
- **EMF Integration**: Built on top of `swift-ecore` for seamless model querying
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
