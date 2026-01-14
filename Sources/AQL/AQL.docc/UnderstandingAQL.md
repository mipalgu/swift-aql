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
