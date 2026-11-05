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

As in Eclipse AQL, `+` and `-` also apply to collections, and `+` joins any value to a
string, with null counting as empty text. They compute the `add` and `sub` services:

```aql
Sequence{'a', 'b'} + Sequence{'b', 'c'}      -- Sequence{'a', 'b', 'b', 'c'}
OrderedSet{'a', 'b'} + Sequence{'b', 'c'}    -- OrderedSet{'a', 'b', 'c'}
Sequence{'a', 'b', 'a'} - Sequence{'a'}      -- Sequence{'b'}
'x' + Sequence{'a', 'b'}                     -- 'xab'
'times ' + 42                                -- 'times 42'
'x' + null                                   -- 'x'
Sequence{'a', 'b'} + null                    -- 'ab'
```

The result of a collection operation has the kind of the left operand, so that an
ordered set or a set leaves out elements it already holds.

## Options

An `AQLExecutionContext` evaluates expressions with the `AQLOptions` it holds in its
`options` property. Create a context with `AQLExecutionContext(options:)` (which gives
the context an execution engine of its own) or
`AQLExecutionContext(executionEngine:options:)`, passing `.standard` for the current
behaviour or `.legacy` for that of version 0.6. Each option can also be set on its own:

```swift
var options = AQLOptions.standard
options.collectionArguments = .firstElement
let context = AQLExecutionContext(options: options)
```

| Option | Default | Alternative (0.6) |
|--|--|--|
| `collectionArguments` | `.whole`: `including`, `append` and `prepend` add a collection argument as one nested element | `.firstElement`: they add only its first element |
| `collectionKinds` | `.distinguished`: collections are sequences, ordered sets, sets or bags, and operations keep the kind of their receiver | `.sequences`: every collection behaves as a sequence |
| `singleValueCollections` | `.set`: an arrow call on a single value sees a set (an empty set for `null`) | `.sequence`: it sees a sequence |
| `containerLookup` | `.resources`: containers are found through the registered resources | `.registeredObjects`: containers are found among the objects the resources list |
| `sequenceUnion` | `.concatenation`: the `union` of a sequence or a bag keeps repeated elements | `.distinct`: it leaves them out |
| `nullAddition` | `.emptyText`: a null operand of `+` counts as empty text (`'x' + null` is `'x'`) | `.null`: it makes the result null |
| `textForm` | `.joined`: the text of a collection joins the text of its elements (`Sequence{'a', 'b'}->toString()` is `'ab'`), and null has no text | `.bracketed`: it is `[a, b]`, and null is `null` |

The raw value of each choice is its command-line spelling (for example `first-element`
or `registered-objects`), so that tools can parse it with `init(rawValue:)` and list the
choices through `allCases`.

`strict` is off in both `.standard` and `.legacy`. Turning it on makes the collection
services reject, with `AQLExecutionError.typeError`, the calls for which Eclipse AQL has
no service, rather than accepting them:

- `union` of a sequence or a bag with an ordered set or a set (an arrow call on a single
  value sees a set, so `'a'->union(Sequence{'b'})` is rejected), and
- `union`, `concat` (`addAll`), `sub` (`difference`, `removeAll`), `intersection`,
  `includesAll` and `excludesAll` with an argument that is not a collection, null
  included. Outside strict mode such an argument counts as a collection holding it, and
  null as an empty collection.

While `collectionKinds` is `.sequences`, every collection is a sequence, so no `union` is
rejected for the kinds of its collections.

```swift
var options = AQLOptions.standard
options.strict = true
```

`AQLOptions(semantics:)` selects `.standard` or `.legacy` from a `ModellingSemantics`
value, and `AQLOptions.fromEnvironment()` reads that choice from the
`SWIFT_MODELLING_SEMANTICS` environment variable (`standard` or `legacy`; `.standard` if it
is unset, and an error for any other value):

```swift
let context = AQLExecutionContext(options: try AQLOptions.fromEnvironment())
```

With `.resources`, each resource answers in the `ContainerLookupScope` configured for it
(`Resource.setContainerLookupScope(_:)`) or for its resource set
(`ResourceSet(defaultContainerLookupScope:)`), and for an object of any resource if no scope
is configured. A resource configured with `.thisResource` does not find the container of an
object held in another resource. `.registeredObjects` does not depend on the scope.

## Compatibility with 0.6

Version 0.6 contexts were created with `AQLExecutionContext(executionEngine:)` or
`AQLExecutionContext(unsetFeatureReads:)`. Both initialisers still exist and still
behave as in 0.6: they use `AQLOptions.legacy`. They are deprecated in favour of the
initialisers that take `options:`; pass `options: .legacy` to keep the 0.6 behaviour.
The behaviours that changed are:

- **Collection arguments**: `Sequence{'a'}->append(Sequence{'b', 'c'})` now yields a
  sequence whose second element is `Sequence{'b', 'c'}`; 0.6 added only `'b'`. Option
  `collectionArguments`; use `.firstElement` for the 0.6 behaviour.
- **Collection kinds**: literals and the conversions `asSequence()`, `asOrderedSet()`,
  `asSet()` and `asBag()` create collections of their kind, and operations keep it. On
  an ordered set or a set, `including` does not repeat an element already present,
  `append`, `prepend` and `insertAt` move it, and `concat`, `collect`, `flatten` and
  navigation leave out repeated results. `sep` yields a sequence, and `closure` an
  ordered set or a set. In 0.6 every collection behaved as a sequence. Option
  `collectionKinds`; use `.sequences` for the 0.6 behaviour.
- **Arrow calls on single values**: `'a'->including('a')` now yields `Set{'a'}`; 0.6
  yielded `Sequence{'a', 'a'}`. Option `singleValueCollections`; use `.sequence` for
  the 0.6 behaviour (it matters only while collection kinds are distinguished).
- **Containers**: `eContainer()`, `ancestors()` and the sibling services ask the
  registered resources, so they also find the containers of nested metamodel contents,
  such as the class of an attribute, which 0.6 did not find. When several objects claim
  the same object, the first resource that knows a container answers, and within a
  resource the first claiming object; 0.6 took the last claim it found. Option
  `containerLookup`; use `.registeredObjects` for the 0.6 behaviour.
- **Union of sequences**: `Sequence{'a', 'b'}->union(Sequence{'b', 'c'})` now yields
  `Sequence{'a', 'b', 'b', 'c'}`, as in Eclipse AQL; 0.6 left out repeated elements for
  every kind. The union of an ordered set or a set still leaves them out. Option
  `sequenceUnion`; use `.distinct` for the 0.6 behaviour.
- **Null in `+`**: `'x' + null` and `null + 'x'` now yield `'x'`, `null + null` yields
  `''`, and `Sequence{'a', 'b'} + null` yields `'ab'`, as in Eclipse AQL; in 0.6 a null
  operand made the result null. Option `nullAddition`; use `.null` for the 0.6 behaviour.
- **Text of collections**: `Sequence{'a', Sequence{'b'}}->toString()` now yields `'ab'`,
  joining the text of the elements as Eclipse AQL does, and `null.toString()` yields `''`;
  0.6 yielded `'[a, [b]]'` and `'null'`. `+` joins collections to strings in the same
  form. Option `textForm`; use `.bracketed` for the 0.6 behaviour.

`AQLService` gained `modifiesModels` and `invoke(_:)`, and `AQLServiceCall` gained
`receiverKind`; the 0.6 initialisers of `AQLService` remain and create services that do
not modify models.

## Containment Queries

`eContainer()`, `ancestors()` and the sibling services ask the resources registered
with `AQLExecutionContext.addResource(_:)` for the container of an object (unless
`containerLookup` is `.registeredObjects`), so they always see the current models. Set `cachesContainmentIndex` on the context to look up
each container only once while the models stay unchanged. Adding a resource drops the
cache, and so does every call of a service created with `modifiesModels: true`. After
changing a model in any other way while caching is on, call
`invalidateContainmentIndex()`.

## Parsing

`AQLParser().parse(_:)` reads one AQL expression from text and returns the expression, the diagnostics (`SourceDiagnostic` values with ranges and the codes of `AQLDiagnosticCode`) and the tokens. Host languages that embed AQL read their own tokens through an `AQLTokenCursor` and shape the nodes through an `AQLParserDelegate`. `AQLSyntax.tokens(in:)` splits text into highlighting tokens and never fails. Every expression node carries an `origin` (its range in the source text) that never takes part in equality, and `AQLTreePrinter` prints a tree as one deterministic line.

## Unset Features

As in the Eclipse Modeling Framework, navigating an unset feature yields its default:
the declared default value or the default of its data type (`false`, zero, the first
enumeration literal) for single-valued attributes, and an empty collection for many-valued
features. Unset strings without a declared default, dates, arbitrary-precision numbers and
single-valued references yield `null`. Create a context with
`AQLExecutionContext(options: .standard, unsetFeatureReads: .undefined)` to read every
unset feature as `null` instead.

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
