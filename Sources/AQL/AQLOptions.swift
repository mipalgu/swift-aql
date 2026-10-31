//
//  AQLOptions.swift
//  AQL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// How `including`, `append` and `prepend` add an argument that is a collection.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLCollectionArguments: String, Sendable, CaseIterable, Hashable {
    /// A collection argument is added whole, as one nested element.
    ///
    /// `Sequence{'a'}->append(Sequence{'b', 'c'})` yields a sequence of two elements, the
    /// second of which is `Sequence{'b', 'c'}`. This is the default.
    case whole

    /// Only the first element of a collection argument is added.
    ///
    /// `Sequence{'a'}->append(Sequence{'b', 'c'})` yields `Sequence{'a', 'b'}`, and an empty
    /// collection argument adds nothing. This is the behaviour of version 0.6.
    case firstElement = "first-element"
}

/// Whether collections keep the kind they are created with.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLCollectionKinds: String, Sendable, CaseIterable, Hashable {
    /// Collections are sequences, ordered sets, sets or bags.
    ///
    /// A collection literal or conversion (such as `asOrderedSet()`) creates a collection of
    /// its kind, and operations keep the kind of their receiver. Ordered sets and sets hold
    /// each element at most once: adding an element that is already present does not repeat
    /// it, `append` and `prepend` move it to the end or the front of an ordered set or set,
    /// and `insertAt` moves it to the given position. `concat`, `collect` and navigation over
    /// an ordered set or a set leave out repeated results. `sep` yields a sequence, and
    /// `closure` an ordered set for an ordered receiver and a set otherwise. This is the
    /// default.
    case distinguished

    /// Every collection behaves as a sequence.
    ///
    /// Collection literals and conversions to ordered sets and sets still leave out repeated
    /// elements, but the collections they create are sequences, and no operation leaves out
    /// or moves an element because it is already present. This is the behaviour of
    /// version 0.6.
    case sequences
}

/// The collection that an arrow call (`->`) sees when its receiver is a single value.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLSingleValueCollections: String, Sendable, CaseIterable, Hashable {
    /// A single value becomes a set holding that value, and null an empty set.
    ///
    /// For example, `'a'->including('a')` yields `Set{'a'}`. This is the default.
    case set

    /// A single value becomes a sequence holding that value, and null an empty sequence.
    ///
    /// For example, `'a'->including('a')` yields `Sequence{'a', 'a'}`. This is the
    /// behaviour of version 0.6.
    case sequence

    /// The kind of the collection that a single value becomes.
    var kind: EcoreCollectionKind {
        switch self {
        case .set: return .set
        case .sequence: return .sequence
        }
    }
}

/// How containment queries find the container of an object.
///
/// The containment queries are `eContainer()`, `ancestors()`, `siblings()`,
/// `precedingSiblings()` and `followingSiblings()`.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLContainerLookup: String, Sendable, CaseIterable, Hashable {
    /// The registered resources are asked for the container of an object.
    ///
    /// The resources are asked in the order they were added, and the first one that knows a
    /// container answers. This finds the containers of all objects of a resource, including
    /// the nested contents of a metamodel such as the class of an attribute. Each resource
    /// answers in the `ContainerLookupScope` configured for it or its resource set, and for
    /// an object of any resource if none is configured. This is the default.
    case resources

    /// The container of an object is the last object that claims it.
    ///
    /// The objects that the registered resources list, taken in resource order, are searched
    /// for containment references that hold the object, and the last one found is the
    /// container. Objects that are only reachable as nested contents of a listed object,
    /// such as the attributes of a class in a metamodel, have no container. This is the
    /// behaviour of version 0.6.
    case registeredObjects = "registered-objects"
}

/// Options that choose between the current behaviour of AQL evaluation and that of
/// version 0.6.
///
/// An ``AQLExecutionContext`` evaluates every expression with the options it holds in
/// ``AQLExecutionContext/options``. Each option selects one of two behaviours: the default,
/// which ``standard`` collects, and the behaviour of version 0.6, which ``legacy``
/// collects. The options are independent, so that a client can keep any one earlier
/// behaviour while adopting the others:
///
/// ```swift
/// var options = AQLOptions.standard
/// options.collectionArguments = .firstElement
/// let context = AQLExecutionContext(options: options)
/// ```
public struct AQLOptions: Sendable, Equatable, Hashable {
    /// How `including`, `append` and `prepend` add an argument that is a collection.
    public var collectionArguments: AQLCollectionArguments

    /// Whether collections keep the kind they are created with.
    public var collectionKinds: AQLCollectionKinds

    /// The collection that an arrow call sees when its receiver is a single value.
    ///
    /// The choice matters only while ``collectionKinds`` is
    /// ``AQLCollectionKinds/distinguished``: otherwise every collection is a sequence.
    public var singleValueCollections: AQLSingleValueCollections

    /// How containment queries find the container of an object.
    public var containerLookup: AQLContainerLookup

    /// Creates options, by default those of ``standard``.
    ///
    /// - Parameters:
    ///   - collectionArguments: How `including`, `append` and `prepend` add a collection
    ///     argument (default: ``AQLCollectionArguments/whole``).
    ///   - collectionKinds: Whether collections keep their kind (default:
    ///     ``AQLCollectionKinds/distinguished``).
    ///   - singleValueCollections: The collection an arrow call sees for a single value
    ///     (default: ``AQLSingleValueCollections/set``).
    ///   - containerLookup: How containment queries find containers (default:
    ///     ``AQLContainerLookup/resources``).
    public init(
        collectionArguments: AQLCollectionArguments = .whole,
        collectionKinds: AQLCollectionKinds = .distinguished,
        singleValueCollections: AQLSingleValueCollections = .set,
        containerLookup: AQLContainerLookup = .resources
    ) {
        self.collectionArguments = collectionArguments
        self.collectionKinds = collectionKinds
        self.singleValueCollections = singleValueCollections
        self.containerLookup = containerLookup
    }

    /// The default options.
    ///
    /// Collection arguments are added whole, collections keep their kind, an arrow call sees
    /// a single value as a set, and containers are found through the registered resources.
    public static let standard = AQLOptions()

    /// The options that reproduce the behaviour of version 0.6.
    ///
    /// Only the first element of a collection argument is added, every collection behaves
    /// as a sequence, an arrow call sees a single value as a sequence, and containers are
    /// found among the objects that the registered resources list.
    public static let legacy = AQLOptions(
        collectionArguments: .firstElement,
        collectionKinds: .sequences,
        singleValueCollections: .sequence,
        containerLookup: .registeredObjects
    )

    /// Creates the options that a choice of semantics selects.
    ///
    /// `ModellingSemantics/standard` selects ``standard`` and
    /// `ModellingSemantics/legacy` selects ``legacy``.
    ///
    /// - Parameter semantics: The semantics to follow.
    public init(semantics: ModellingSemantics) {
        switch semantics {
        case .standard: self = .standard
        case .legacy: self = .legacy
        }
    }

    /// Creates the options that an environment selects.
    ///
    /// The `SWIFT_MODELLING_SEMANTICS` variable (`ModellingSemantics/environmentVariable`)
    /// selects ``standard`` or ``legacy`` by its value, `standard` or `legacy`. Without the
    /// variable, or with an empty value, the options are ``standard``. A context can take
    /// its options from the environment of the process once, when it is created:
    ///
    /// ```swift
    /// let context = AQLExecutionContext(options: try AQLOptions.fromEnvironment())
    /// ```
    ///
    /// - Parameter environment: The environment variables to read; by default those of the
    ///   current process.
    /// - Returns: The selected options.
    /// - Throws: `ModellingSemanticsError/invalidValue(_:variable:)` if the variable holds
    ///   any other value.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws(ModellingSemanticsError) -> AQLOptions {
        AQLOptions(semantics: try ModellingSemantics.fromEnvironment(environment) ?? .standard)
    }
}
