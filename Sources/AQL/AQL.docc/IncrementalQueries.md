# Incremental Queries

Keep the values of AQL expressions up to date as the models change.

## Overview

An ``AQLIncrementalExpression`` evaluates an expression once while recording what it reads
from the models: the features navigated, the classes whose instances `allInstances`
enumerates, and the containers that containment queries look up. After the models have been
changed through the editing operations of `Resource`, ``AQLIncrementalExpression/update(for:)``
evaluates the expression again only if a change affects something that it read, and reports
an ``AQLQueryChange`` that lists the elements added to and removed from the value. The value
after an update is always the value that a fresh evaluation over the changed models gives.

An ``AQLQueryObserver`` keeps many expressions up to date at once. It watches the resources of
its context, and each ``AQLQueryObserver/refresh()`` re-evaluates only the expressions that
the changes collected since the previous refresh affect, which it finds through an index of
their dependencies.

```swift
let observer = AQLQueryObserver(context: context)
await observer.start()
let adults = AQLIncrementalExpression(
    expression: AQLParser().parse("company::Person.allInstances()->select(p | p.age >= 18)").expression!,
    context: context)
try await observer.register(adults) { change in
    print("added \(change.added.count), removed \(change.removed.count)")
}
try await resource.eSetWithChanges(objectId: person.id, feature: "age", value: 21)
try await observer.refresh()
```

Incremental evaluation is opt-in. Evaluating an expression directly records nothing and
behaves exactly as before.

### Requirements and Limits

The context should hold the models: add each resource with
``AQLExecutionContext/addResource(_:)`` and register it with the context's execution engine,
so that navigation reads the current state of objects. Changes must be made through the
editing operations that report them.

Calls of services registered by clients, `eInverse()`, and derived or volatile features may
read anything, so an expression that uses them is evaluated again after every change.
Expressions are re-evaluated as a whole: a change that affects one element of a large
collection re-evaluates the whole expression.

## Topics

### Incremental Evaluation

- ``AQLIncrementalExpression``
- ``AQLQueryChange``
- ``AQLQueryObserver``
- ``AQLQueryRegistration``
- ``AQLQueryUpdate``
- ``AQLExecutionContext/recordingDependencies(_:)``
