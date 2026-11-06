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

### Dot and Arrow Calls on Collections

The arrow calls a collection service on the collection itself. The dot applies a call to
each element of a collection, just as it navigates a feature of each element, even when a
collection service of the same name exists. With `names` holding `Sequence{'Ann', 'Bob'}`:

```aql
names->size()                -- 2, the number of names
names.size()                 -- Sequence{3, 3}, the length of each name
names.toUpper()              -- Sequence{'ANN', 'BOB'}
OrderedSet{'a', 'b'}.size()  -- OrderedSet{1}, as an ordered set keeps 1 only once
Sequence{1, 2}.size()        -- Sequence{}, as an integer has no size
'Ann'->size()                -- 1, as a single value is a collection of one
null->size()                 -- 0, as null is an empty collection
```

A dot call walks nested collections, flattens the results by one level, leaves out null
results and elements without a service of that name, and keeps the kind of its receiver, so
that a dot call on an ordered set or a set yields an ordered set or a set. Write collection
services such as `size`, `first`, `sum` and `select` with the arrow: the arrow gives the same
result whatever ``AQLOptions/dotCalls`` says (see
<doc:UnderstandingAQL#Options-and-Compatibility-with-0.6>).

When a dot call reaches an element without the service while the collection has a service of
that name, as in `Sequence{1, 2}.size()`, the context records a warning with the code
``AQLDiagnosticCode/dotCallOnElements`` and the range of the call, suggesting `->size()`.
``AQLExecutionContext/diagnostics`` lists the warnings oldest first, each one once, and keeps
a warning even when strict mode then raises an error;
``AQLExecutionContext/clearDiagnostics()`` empties the list.

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
| `at(index)` | Element at a one-based index | `col->at(1)` |

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
| `concat(other)`, `add(other)`, `+` | Append the elements of a collection | `col1 + col2` |
| `sub(other)`, `-` | Remove every occurrence of the elements of a collection | `col1 - col2` |
| `intersection(other)` | Common elements | `col1->intersection(col2)` |
| `excluding(elem)` | Remove every occurrence of an element | `col->excluding(elem)` |
| `including(elem)` | Add element | `col->including(elem)` |

Each of these yields a collection of the kind of its receiver (the left operand of `+` and
`-`). A sequence or a bag keeps repeated elements and an ordered set or a set leaves them
out, so that `union`, `concat`, `add` and `+` agree:

```aql
Sequence{'a', 'b'}->union(Sequence{'b', 'c'})     -- Sequence{'a', 'b', 'b', 'c'}
Sequence{'a', 'b'} + OrderedSet{'b', 'c'}         -- Sequence{'a', 'b', 'b', 'c'}
OrderedSet{'a', 'b'}->union(OrderedSet{'b', 'c'}) -- OrderedSet{'a', 'b', 'c'}
OrderedSet{'a', 'b'} + Sequence{'b', 'c'}         -- OrderedSet{'a', 'b', 'c'}
Sequence{'a', 'b', 'a'} - Sequence{'a'}           -- Sequence{'b'}
Sequence{'a', 'b', 'a'}->intersection(Sequence{'a'}) -- Sequence{'a', 'a'}
```

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
| `concat(str)` | Concatenate (null adds nothing) | `name.concat('.swift')` |
| `+`, `add(value)` | Append the text of any value (null has no text) | `'times ' + 42` |
| `toString()` | The text of any value; a collection joins the text of its elements | `col->toString()` |
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
| `+`, `add(n)` | Addition (with a string operand, concatenation of text) | `a + b`, `1.add(2)` |
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
| `eClass()` | Get the metaclass | `e.eClass()` |
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

## Services

Operations on strings, collections, numbers, booleans and model objects are provided as
services. The standard library of Acceleo and AQL string, collection and `EObject` services
is available in every ``AQLExecutionContext``, and clients add their own by registering an
``AQLServiceProvider``:

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

The calls `receiver.name(args)`, `receiver->name(args)` and `name(args)` search the
registered services, most recent first, and then the standard library. A dot call on a
collection searches them for each element (see
<doc:UnderstandingAQL#Dot-and-Arrow-Calls-on-Collections>). Services may be
asynchronous and use `call.context` to navigate the model. Iterator arguments (`x | body`)
arrive as ``AQLLambda`` values, and type arguments (`ecore::EClass`) as
``AQLTypeDescriptor`` values. A service that changes a model declares so with
`modifiesModels: true`.

As in Eclipse AQL, `+` and `-` also apply to collections, and `+` joins any value to a
string, with null counting as empty text. They compute the `add` and `sub` services. The
result of a collection operation has the kind of the left operand, so that an ordered set
or a set leaves out elements it already holds:

```aql
Sequence{'a', 'b'} + Sequence{'b', 'c'}      -- Sequence{'a', 'b', 'b', 'c'}
OrderedSet{'a', 'b'} + Sequence{'b', 'c'}    -- OrderedSet{'a', 'b', 'c'}
Sequence{'a', 'b', 'a'} - Sequence{'a'}      -- Sequence{'b'}
'x' + Sequence{'a', 'b'}                     -- 'xab'
'times ' + 42                                -- 'times 42'
'x' + null                                   -- 'x'
Sequence{'a', 'b'} + null                    -- 'ab'
```

## Containment Queries

`eContainer()`, `ancestors()` and the sibling services ask the resources registered with
``AQLExecutionContext/addResource(_:)`` for the container of an object (unless
``AQLOptions/containerLookup`` is ``AQLContainerLookup/registeredObjects``), so they always
see the current models. Set ``AQLExecutionContext/cachesContainmentIndex`` to look up each
container only once while the models stay unchanged. Adding a resource drops the cache, and
so does every call of a service created with `modifiesModels: true`. After changing a model
in any other way while caching is on, call
``AQLExecutionContext/invalidateContainmentIndex()``.

## Parsing

``AQLParser/parse(_:)`` reads one AQL expression from text and returns an
``AQLParseResult`` holding the expression, the diagnostics (`SourceDiagnostic` values with
ranges and the codes of ``AQLDiagnosticCode``) and the tokens. Host languages that embed
AQL read their own tokens through an ``AQLTokenCursor`` and shape the nodes through an
``AQLParserDelegate``. ``AQLSyntax/tokens(in:)`` splits text into highlighting tokens and
never fails. Every expression node carries an `origin`, its range in the source text, which
never takes part in equality, and ``AQLTreePrinter`` prints a tree as one deterministic
line.

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
| ``AQLOptions/sequenceUnion`` | ``AQLSequenceUnion/concatenation`` | ``AQLSequenceUnion/distinct`` |
| ``AQLOptions/nullAddition`` | ``AQLNullAddition/emptyText`` | ``AQLNullAddition/null`` |
| ``AQLOptions/textForm`` | ``AQLTextForm/joined`` | ``AQLTextForm/bracketed`` |
| ``AQLOptions/dotCalls`` | ``AQLDotCalls/eachElement`` | ``AQLDotCalls/collection`` |

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
Sequence{'a', 'b'}->union(Sequence{'b', 'c'})
    -- concatenation:  Sequence{'a', 'b', 'b', 'c'}
    -- distinct:       Sequence{'a', 'b', 'c'}
'x' + null
    -- empty-text:     'x'
    -- null:           null
Sequence{'a', Sequence{'b'}}->toString()
    -- joined:         'ab'
    -- bracketed:      '[a, [b]]'
Sequence{'ab', 'c'}.size()
    -- each-element:   Sequence{2, 1}
    -- collection:     2
```

The raw value of each choice is its command-line spelling (for example `first-element`
or `registered-objects`), so that tools can parse it with `init(rawValue:)` and list the
choices through `allCases`.

The behaviours that changed since version 0.6, besides those shown above, are:

- **Collection kinds**: on an ordered set or a set, `including` does not repeat an element
  already present, `append`, `prepend` and `insertAt` move it, and `concat`, `collect`,
  `flatten` and navigation leave out repeated results. `sep` yields a sequence, and
  `closure` an ordered set or a set. In version 0.6 every collection behaved as a sequence.
- **Null in `+`**: `null + 'x'` yields `'x'` and `null + null` yields `''`.
- **Text of collections**: `null.toString()` yields `''` rather than `'null'`, and `+`
  joins collections to strings in the same form.
- **Dot calls on collections**: with ``AQLDotCalls/eachElement``, as in Eclipse AQL, a dot
  call on a collection applies to each element, so `names.size()` gives the length of each
  name. With ``AQLDotCalls/collection``, as in version 0.6, it calls the collection service,
  so `names.size()` gives the number of names. Navigating a feature, as in
  `self.attributes.name`, collects it under both, but an element without the feature is
  left out with ``AQLDotCalls/eachElement`` and an error with ``AQLDotCalls/collection``.
  An arrow call, as in `names->size()`, behaves the same under both.
- **Services**: `AQLService` gained `modifiesModels` and `invoke(_:)`, and
  `AQLServiceCall` gained `receiverKind`. The initialisers of version 0.6 remain and
  create services that do not modify models.

``AQLOptions/strict`` is off under both ``AQLOptions/standard`` and ``AQLOptions/legacy``.
Turning it on makes the collection services raise ``AQLExecutionError/typeError(_:)`` for
the calls that Eclipse AQL has no service for: a `union` of a sequence or a bag with an
ordered set or a set, and `union`, `concat`, `sub`, `intersection`, `includesAll` or
`excludesAll` with an argument that is not a collection, null included:

```aql
Sequence{'a'}->union(OrderedSet{'b'})   -- Sequence{'a', 'b'}, or an error in strict mode
Sequence{'a'}->concat('b')              -- Sequence{'a', 'b'}, or an error in strict mode
```

With ``AQLDotCalls/eachElement``, strict mode also makes a dot call or a navigation over a
collection an error when none of its elements has the service or the feature; otherwise those
elements are left out:

```aql
Sequence{1, 2}.size()                   -- Sequence{}, or an error in strict mode
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
- ``AQLCollectionServices`` - Collection operations reference
- ``AQLExecutionContext`` - Execution configuration

## See Also

- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
