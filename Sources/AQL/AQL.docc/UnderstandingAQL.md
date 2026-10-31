# Understanding AQL

Learn the fundamental concepts of the Acceleo Query Language.

## Overview

AQL (Acceleo Query Language)
([AQL](https://eclipse.dev/acceleo/documentation/)) is an
expression language designed for querying models. It provides a concise syntax for
navigating model structures, filtering collections, and computing values.

AQL is based on OMG OCL (Object Constraint Language)
([OMG OCL](https://www.omg.org/spec/OCL/))
semantics but with a simplified, more accessible syntax.

## Expression Types

### Literals

AQL supports various literal types:

```aql
'Hello'         -- String
42              -- Integer
3.14            -- Real/Double
true            -- Boolean
false           -- Boolean
null            -- Null value
```

### Variables

Access variables defined in the context:

```aql
self            -- The current context object
myVariable      -- A named variable
```

### Navigation

Navigate model structures using dot notation:

```aql
self.name                   -- Attribute access
self.package                -- Single reference
self.attributes             -- Collection reference
self.package.name           -- Chained navigation
self.package.classes.name   -- Navigation through collections
```

### Operation Calls

Call operations on values:

```aql
self.name.toUpper()                    -- Instance operation
self.attributes->size()                -- Collection operation
self.name.substring(0, 5)              -- Operation with arguments
```

## Collection Operations

Collections are central to AQL. Operations use the `->` arrow syntax.

### Collection Kinds

A collection is a `Sequence`, an `OrderedSet`, a `Set` or a `Bag`, as written in
its literal (`OrderedSet{'a', 'b'}`) or produced by `asSequence()`, `asOrderedSet()`,
`asSet()` or `asBag()`. All kinds keep their elements in order. Ordered sets and sets
hold each element at most once; sequences and bags may repeat elements. Calling an
arrow operation on a single value treats it as a set holding that value. (These are the
behaviours of ``AQLOptions/standard``; see
<doc:UnderstandingAQL#Options-and-Compatibility-with-0.6> for those of version 0.6.)

Operations such as `select`, `collect`, `sortedBy`, `union` and `including` return a
collection of the same kind as the one they are called on. Adding an element that an
ordered set or a set already holds does not repeat it:

```aql
OrderedSet{'a', 'b', 'c'}->including('b')   -- OrderedSet{'a', 'b', 'c'}
OrderedSet{'a', 'b', 'c'}->append('b')      -- OrderedSet{'a', 'c', 'b'}
OrderedSet{'a', 'b', 'c'}->prepend('b')     -- OrderedSet{'b', 'a', 'c'}
Sequence{'a', 'b', 'c'}->append('b')        -- Sequence{'a', 'b', 'c', 'b'}
```

### Basic Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `size()` | Number of elements | `col->size()` |
| `isEmpty()` | True if no elements | `col->isEmpty()` |
| `notEmpty()` | True if has elements | `col->notEmpty()` |
| `first()` | First element | `col->first()` |
| `last()` | Last element | `col->last()` |
| `at(index)` | Element at index | `col->at(0)` |

### Filtering

| Operation | Description | Example |
|-----------|-------------|---------|
| `select(cond)` | Keep matching elements | `col->select(e \| e.isPublic)` |
| `reject(cond)` | Remove matching elements | `col->reject(e \| e.isDerived)` |

### Transformation

| Operation | Description | Example |
|-----------|-------------|---------|
| `collect(expr)` | Map to new values | `col->collect(e \| e.name)` |
| `flatten()` | Flatten nested collections | `col->flatten()` |

### Testing

| Operation | Description | Example |
|-----------|-------------|---------|
| `forAll(cond)` | All elements match | `col->forAll(e \| e.name <> '')` |
| `exists(cond)` | Any element matches | `col->exists(e \| e.isId)` |
| `one(cond)` | Exactly one matches | `col->one(e \| e.isId)` |
| `includes(elem)` | Contains element | `col->includes(myElem)` |
| `excludes(elem)` | Doesn't contain | `col->excludes(myElem)` |

### Set Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `union(other)` | Combine collections | `col1->union(col2)` |
| `intersection(other)` | Common elements | `col1->intersection(col2)` |
| `excluding(elem)` | Remove specific element | `col->excluding(elem)` |
| `including(elem)` | Add element | `col->including(elem)` |

### Aggregation

| Operation | Description | Example |
|-----------|-------------|---------|
| `sum()` | Sum of numbers | `salaries->sum()` |
| `min()` | Minimum value | `ages->min()` |
| `max()` | Maximum value | `ages->max()` |

## String Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `toUpper()` | Uppercase | `name.toUpper()` |
| `toLower()` | Lowercase | `name.toLower()` |
| `concat(str)` | Concatenate | `name.concat('.swift')` |
| `substring(start, end)` | Extract portion | `name.substring(0, 5)` |
| `size()` | Length | `name.size()` |
| `startsWith(prefix)` | Check prefix | `name.startsWith('get')` |
| `endsWith(suffix)` | Check suffix | `name.endsWith('.swift')` |
| `contains(str)` | Contains substring | `name.contains('test')` |
| `replaceAll(old, new)` | Replace all | `name.replaceAll('_', '')` |
| `trim()` | Remove whitespace | `name.trim()` |

## Boolean Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `and` | Logical AND | `a and b` |
| `or` | Logical OR | `a or b` |
| `not` | Logical NOT | `not a` |
| `implies` | Implication | `a implies b` |

## Comparison Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `=` | Equal | `a = b` |
| `<>` | Not equal | `a <> b` |
| `<` | Less than | `a < b` |
| `<=` | Less or equal | `a <= b` |
| `>` | Greater than | `a > b` |
| `>=` | Greater or equal | `a >= b` |

## Numeric Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `+` | Addition | `a + b` |
| `-` | Subtraction | `a - b` |
| `*` | Multiplication | `a * b` |
| `/` | Division | `a / b` |
| `mod` | Modulo | `a mod b` |
| `abs()` | Absolute value | `(-5).abs()` |
| `floor()` | Floor | `3.7.floor()` |
| `round()` | Round | `3.5.round()` |

## Type Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| `oclIsKindOf(Type)` | Instance of type or subtype | `e.oclIsKindOf(Entity)` |
| `oclIsTypeOf(Type)` | Exact type match | `e.oclIsTypeOf(Entity)` |
| `oclAsType(Type)` | Cast to type | `e.oclAsType(Entity)` |
| `oclType()` | Get the type | `e.oclType()` |
| `oclIsUndefined()` | Is null/undefined | `e.oclIsUndefined()` |

## Conditional Expressions

### If-Then-Else

```aql
if condition then
    trueValue
else
    falseValue
endif
```

Example:
```aql
if self.isAbstract then 'abstract ' else '' endif
```

### Nested Conditionals

```aql
if self.visibility = 'public' then 'public'
else if self.visibility = 'protected' then 'protected'
else 'private'
endif endif
```

## Let Expressions

Define local variables:

```aql
let name = self.name.toUpper() in
name.concat('_CONSTANT')
```

Multiple bindings:

```aql
let upper = self.name.toUpper() in
let prefix = 'PREFIX_' in
prefix.concat(upper)
```

## Lambda Expressions

Used in collection operations:

```aql
-- Simple lambda
self.attributes->select(a | a.isRequired)

-- Lambda with type annotation
self.attributes->select(a : Attribute | a.isRequired)

-- Multiple conditions in lambda
self.attributes->select(a | a.isRequired and a.visibility = 'public')
```

## Null Safety

AQL handles null values gracefully:

```aql
-- Check for null
self.package.oclIsUndefined()

-- Safe navigation (returns null if package is null)
self.package.name

-- Default value pattern
if self.package.oclIsUndefined() then 'default' else self.package.name endif
```

## Unset Features

Navigating a feature that has not been set yields what the Eclipse Modeling Framework's
`eGet` yields, both for dot navigation and for the `eGet` service:

- An unset single-valued attribute reads as its declared default value or, without one, as
  the default of its data type: `false` for booleans, zero for numbers, and the first literal
  of an enumeration. An unset `isAbstract` flag is therefore `false`, so `not self.isAbstract`
  is `true`.
- An unset many-valued attribute or reference reads as an empty collection, so `->size()` is
  zero and `oclIsUndefined()` is `false`.
- An unset string attribute without a declared default, and an unset single-valued
  reference, read as `null`, so `oclIsUndefined()` is `true`.

To find out whether a feature has been set, select the non-standard undefined mode, in which
every unset feature reads as `null`. Pass it when creating a context, or switch the engine of
an existing context:

```swift
// A new context whose own engine reads unset features as null
let context = AQLExecutionContext(options: .standard, unsetFeatureReads: .undefined)

// An existing context switched to the same mode
await existingContext.executionEngine.setUnsetFeatureReads(.undefined)
```

## Options and Compatibility with 0.6

An ``AQLExecutionContext`` evaluates expressions with the ``AQLOptions`` in its
``AQLExecutionContext/options`` property. ``AQLOptions/standard`` holds the defaults and
``AQLOptions/legacy`` the behaviours of version 0.6. Contexts created with the
initialisers of version 0.6, ``AQLExecutionContext/init(executionEngine:serviceProviders:)``
and ``AQLExecutionContext/init(unsetFeatureReads:serviceProviders:)``, use
``AQLOptions/legacy``; those initialisers are deprecated in favour of
``AQLExecutionContext/init(executionEngine:options:serviceProviders:)`` and
``AQLExecutionContext/init(options:unsetFeatureReads:serviceProviders:)``. Each option
can be set on its own:

| Option | Default | Version 0.6 |
|--|--|--|
| ``AQLOptions/collectionArguments`` | ``AQLCollectionArguments/whole`` | ``AQLCollectionArguments/firstElement`` |
| ``AQLOptions/collectionKinds`` | ``AQLCollectionKinds/distinguished`` | ``AQLCollectionKinds/sequences`` |
| ``AQLOptions/singleValueCollections`` | ``AQLSingleValueCollections/set`` | ``AQLSingleValueCollections/sequence`` |
| ``AQLOptions/containerLookup`` | ``AQLContainerLookup/resources`` | ``AQLContainerLookup/registeredObjects`` |

The options make these differences:

```aql
Sequence{'a'}->append(Sequence{'b', 'c'})
    -- whole:          Sequence{'a', Sequence{'b', 'c'}}
    -- first-element:  Sequence{'a', 'b'}
OrderedSet{'a', 'b', 'c'}->append('b')
    -- distinguished:  OrderedSet{'a', 'c', 'b'}
    -- sequences:      Sequence{'a', 'b', 'c', 'b'}
'a'->including('a')
    -- set:            Set{'a'}
    -- sequence:       Sequence{'a', 'a'}
```

With ``AQLContainerLookup/resources``, `eContainer()`, `ancestors()` and the sibling
services ask the registered resources for containers, which also finds the containers of
nested metamodel contents such as the class of an attribute; when several objects claim
the same object, the first resource that knows a container answers. With
``AQLContainerLookup/registeredObjects``, as in version 0.6, containers are found among
the objects that the resources list, and the last claim found wins.

With ``AQLContainerLookup/resources``, each resource answers in the container lookup scope
configured for it, through `Resource.container(ofIdentifier:scope:)`: its own scope, else the
default of its resource set. A resource for which no scope is configured answers for an
object of any resource, as before the scope could be configured. A resource configured with
`ContainerLookupScope.thisResource` answers only for the objects that it can resolve itself,
or that their container embeds as a value, so the container of an object held in another
resource is not found. ``AQLContainerLookup/registeredObjects`` does not depend on the scope.

```swift
let resourceSet = ResourceSet(defaultContainerLookupScope: .thisResource)
```

The ``AQLOptions/init(semantics:)`` initialiser selects ``AQLOptions/standard`` or
``AQLOptions/legacy`` from a `ModellingSemantics` value, and
``AQLOptions/fromEnvironment(_:)`` reads that choice from the `SWIFT_MODELLING_SEMANTICS`
environment variable (`standard` or `legacy`; ``AQLOptions/standard`` if it is unset):

```swift
let context = AQLExecutionContext(options: try AQLOptions.fromEnvironment())
```

A context keeps its options for every expression it evaluates, until its
``AQLExecutionContext/options`` are changed.

## Evaluation Order

1. **Literals and variables** are evaluated first
2. **Navigation** proceeds left to right
3. **Operations** are called on their receivers
4. **Lambdas** create closures evaluated per element
5. **Conditionals** evaluate branches lazily

## Best Practices

1. **Use meaningful lambda parameters**: `select(attr | ...)` not `select(x | ...)`
2. **Chain operations**: `select(...)->collect(...)->first()` for efficiency
3. **Check for null**: Use `oclIsUndefined()` before nullable navigation
4. **Prefer `select` over iteration**: More declarative and efficient
5. **Extract complex queries**: Define as separate named queries

## OCL Compatibility

AQL is based on OCL but differs in:

- **Arrow syntax**: AQL uses `->` for all collection operations
- **Simplified syntax**: Less verbose than full OCL
- **Lambda syntax**: Uses `|` instead of more complex OCL syntax

## Next Steps

- <doc:GettingStarted> - Practical examples
- ``AQLExpression`` - Expression API
- ``AQLCollectionOperations`` - Collection operations reference
- ``AQLExecutionContext`` - Execution configuration

## See Also

- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
