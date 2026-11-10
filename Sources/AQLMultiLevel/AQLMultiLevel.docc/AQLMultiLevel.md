# ``AQLMultiLevel``

@Metadata {
    @DisplayName("AQLMultiLevel")
}

AQL for multi-level models: deep constraints and deep services.

## Overview

The MultiLevel library of swift-ecore presents each level of a deep model as a deep level
view, in which every type facet above the level is a class whose supertypes include its
ontological type. Standard AQL is therefore already deep within a view:
`self.oclIsKindOf(ProductType)` holds for a book two levels below its product type, and
`ProductType.allInstances()` yields the deep instances at the level.

``AQLDeepConstraintEvaluator`` evaluates the AQL bodies of deep constraints at the levels
their potencies select:

```swift
let diagnostics = await model.validate(evaluator: AQLDeepConstraintEvaluator())
```

``AQLMultiLevelServices`` adds services for what the views express only implicitly, such as
`self.ontologicalType()`, `self.level()`, `ProductType.deepInstances()` and
`self.typeAtLevel(1).vat` (see ``AQLMultiLevelServiceName``). They apply only to objects of
the views, so other objects keep the standard services. MTL templates use them through the
`serviceProviders` parameter of their generator.

## Topics

### Constraints

- ``AQLDeepConstraintEvaluator``
- ``AQLMultiLevelError``
- ``AQLMultiLevelSyntax``

### Services

- ``AQLMultiLevelServices``
- ``AQLMultiLevelServiceName``
