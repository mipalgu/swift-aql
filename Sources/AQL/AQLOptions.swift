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

/// Whether `union` keeps repeated elements when its receiver is a sequence or a bag.
///
/// A union whose receiver is an ordered set or a set leaves out repeated elements under
/// either choice.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLSequenceUnion: String, Sendable, CaseIterable, Hashable {
    /// The union of a sequence or a bag holds every element of both collections.
    ///
    /// `Sequence{'a', 'b'}->union(Sequence{'b', 'c'})` yields
    /// `Sequence{'a', 'b', 'b', 'c'}`, as `Sequence{'a', 'b'} + Sequence{'b', 'c'}` does.
    /// This is the default.
    case concatenation

    /// The union of a sequence or a bag leaves out repeated elements.
    ///
    /// `Sequence{'a', 'b'}->union(Sequence{'b', 'c'})` yields `Sequence{'a', 'b', 'c'}`, and
    /// `Sequence{'a', 'a'}->union(Sequence{})` yields `Sequence{'a'}`. This is the behaviour
    /// of version 0.6.
    case distinct
}

/// What `+` and the `add` services make of a null operand.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLNullAddition: String, Sendable, CaseIterable, Hashable {
    /// A null operand counts as empty text, so the result is the text of the other operand.
    ///
    /// `'x' + null` and `null + 'x'` yield `'x'`, `null + null` yields `''`,
    /// `Sequence{'a', 'b'} + null` yields the text of the sequence (`'ab'`), and `null + 1`
    /// yields `'1'`. This is the default.
    case emptyText = "empty-text"

    /// A null operand makes the result null.
    ///
    /// `'x' + null` yields null. This is the behaviour of version 0.6.
    case null
}

/// The text of a value, as `toString()` gives it and `+` joins it to a string.
///
/// Under either choice, a string is its own text, and numbers, booleans and objects have the
/// text that `AQLValues/description(of:)` gives them.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLTextForm: String, Sendable, CaseIterable, Hashable {
    /// The text of a collection joins the text of its elements without separators.
    ///
    /// Nested collections contribute the text of their elements in turn, and null has no
    /// text: `Sequence{'a', Sequence{'b', 1}}->toString()` yields `'ab1'`, and
    /// `null.toString()` yields `''`. This is the default.
    case joined

    /// The text of a collection lists the text of its elements in brackets.
    ///
    /// `Sequence{'a', Sequence{'b', 1}}->toString()` yields `'[a, [b, 1]]'`, and
    /// `null.toString()` yields `'null'`. This is the behaviour of version 0.6.
    case bracketed

    /// The text of a value in this form.
    ///
    /// - Parameter value: The value to format.
    /// - Returns: The text of the value.
    func text(of value: (any EcoreValue)?) -> String {
        switch self {
        case .bracketed:
            return AQLValues.description(of: value)
        case .joined:
            guard let value else { return "" }
            if let items = AQLValues.elements(of: value) { return items.map { text(of: $0) }.joined() }
            return AQLValues.description(of: value)
        }
    }
}

/// What a call written with a dot (`.`) does when its receiver is a collection.
///
/// Navigating a feature without parentheses, such as `objects.name`, applies to each element
/// of a collection under either choice. Arrow calls (`->`) and operators such as `+` always
/// apply to the collection itself.
///
/// The raw value of each case is its lower-case, hyphenated command-line spelling, so that
/// a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum AQLDotCalls: String, Sendable, CaseIterable, Hashable {
    /// A dot call on a collection calls the service on each element, as Eclipse AQL does.
    ///
    /// An element that is itself a collection has the call applied to each of its elements
    /// in turn. The results are collected in a collection of the kind of the receiver: a
    /// result that is a collection contributes its elements, and a null result, or an element
    /// that has no service of the name for arguments of their types, contributes nothing. An ordered set or a set leaves
    /// out repeated results. For example, `Sequence{'a', 'bc'}.size()` yields
    /// `Sequence{1, 2}`, `OrderedSet{'a', 'b'}.size()` yields `OrderedSet{1}`, and
    /// `Sequence{1, 2}.size()` yields `Sequence{}`, as integers have no `size` service; use
    /// `Sequence{1, 2}->size()` for the size of the collection.
    ///
    /// The same rules apply to navigating a feature over a collection: an element without
    /// the feature contributes nothing. In strict mode (see ``AQLOptions/strict``), a dot
    /// call or a navigation over a collection none of whose elements has the service or the
    /// feature raises an error. This is the default.
    case eachElement = "each-element"

    /// A dot call on a collection calls the service on the collection.
    ///
    /// `Sequence{'a', 'bc'}.size()` yields `2`, as `Sequence{'a', 'bc'}->size()` does, and a
    /// navigation over a collection fails if an element is an object without the feature.
    /// This is the behaviour of version 0.6.
    case collection
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
///
/// ``strict`` is the exception: both presets leave it off, and turning it on makes the
/// collection services reject the arguments that Eclipse AQL rejects, and dot calls on
/// collections reject services and features that no element has.
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

    /// Whether `union` keeps repeated elements when its receiver is a sequence or a bag.
    public var sequenceUnion: AQLSequenceUnion

    /// What `+` and the `add` services make of a null operand.
    public var nullAddition: AQLNullAddition

    /// The text of a value, as `toString()` gives it and `+` joins it to a string.
    public var textForm: AQLTextForm

    /// What a call written with a dot does when its receiver is a collection.
    public var dotCalls: AQLDotCalls

    /// Whether collection services and dot calls reject what Eclipse AQL rejects.
    ///
    /// Outside strict mode, which is the default of both ``standard`` and ``legacy``, the
    /// collection services accept some arguments for which Eclipse AQL has no service. In
    /// strict mode, they raise ``AQLExecutionError/typeError(_:)`` for them instead:
    ///
    /// - `union` with an argument whose kind does not match its receiver: a sequence or a
    ///   bag with an ordered set or a set, or an ordered set or a set with a sequence or a
    ///   bag. A value that is not a collection becomes a set for an arrow call (see
    ///   ``singleValueCollections``), so `'a'->union(Sequence{'b'})` is rejected.
    /// - `union`, `concat` (`addAll`), `sub` (`difference`, `removeAll`), `intersection`,
    ///   `includesAll` and `excludesAll` with an argument that is not a collection,
    ///   null included. Outside strict mode, such an argument counts as a collection holding
    ///   it, and null as an empty collection.
    ///
    /// While ``dotCalls`` is ``AQLDotCalls/eachElement``, strict mode also rejects a dot call
    /// or a navigation over a collection when none of the elements it reaches has the service
    /// or the feature, such as `Sequence{1, 2}.size()`, by raising
    /// ``AQLExecutionError/invalidOperation(_:)``. Outside strict mode, the result leaves such
    /// elements out.
    ///
    /// While ``collectionKinds`` is ``AQLCollectionKinds/sequences``, every collection is a
    /// sequence, so that no union is rejected for the kinds of its collections.
    public var strict: Bool

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
    ///   - sequenceUnion: Whether the union of a sequence or a bag keeps repeated elements
    ///     (default: ``AQLSequenceUnion/concatenation``).
    ///   - nullAddition: What `+` makes of a null operand (default:
    ///     ``AQLNullAddition/emptyText``).
    ///   - textForm: The text of values (default: ``AQLTextForm/joined``).
    ///   - dotCalls: What a dot call on a collection does (default:
    ///     ``AQLDotCalls/eachElement``).
    ///   - strict: Whether collection services and dot calls reject what Eclipse AQL
    ///     rejects (default: `false`).
    public init(
        collectionArguments: AQLCollectionArguments = .whole,
        collectionKinds: AQLCollectionKinds = .distinguished,
        singleValueCollections: AQLSingleValueCollections = .set,
        containerLookup: AQLContainerLookup = .resources,
        sequenceUnion: AQLSequenceUnion = .concatenation,
        nullAddition: AQLNullAddition = .emptyText,
        textForm: AQLTextForm = .joined,
        dotCalls: AQLDotCalls = .eachElement,
        strict: Bool = false
    ) {
        self.collectionArguments = collectionArguments
        self.collectionKinds = collectionKinds
        self.singleValueCollections = singleValueCollections
        self.containerLookup = containerLookup
        self.sequenceUnion = sequenceUnion
        self.nullAddition = nullAddition
        self.textForm = textForm
        self.dotCalls = dotCalls
        self.strict = strict
    }

    /// The default options.
    ///
    /// Collection arguments are added whole, collections keep their kind, an arrow call sees
    /// a single value as a set, containers are found through the registered resources, the
    /// union of a sequence or a bag keeps repeated elements, `+` counts null as empty text,
    /// the text of a collection joins the text of its elements, and a dot call on a
    /// collection applies to each element. Strict mode is off.
    public static let standard = AQLOptions()

    /// The options that reproduce the behaviour of version 0.6.
    ///
    /// Only the first element of a collection argument is added, every collection behaves
    /// as a sequence, an arrow call sees a single value as a sequence, containers are found
    /// among the objects that the registered resources list, a union leaves out repeated
    /// elements, `+` with a null operand yields null, the text of a collection lists the
    /// text of its elements in brackets, and a dot call on a collection applies to the
    /// collection. Strict mode is off, as for ``standard``.
    public static let legacy = AQLOptions(
        collectionArguments: .firstElement,
        collectionKinds: .sequences,
        singleValueCollections: .sequence,
        containerLookup: .registeredObjects,
        sequenceUnion: .distinct,
        nullAddition: .null,
        textForm: .bracketed,
        dotCalls: .collection
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
