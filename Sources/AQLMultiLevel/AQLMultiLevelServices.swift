//
//  AQLMultiLevelServices.swift
//  AQLMultiLevel
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
public import AQL
public import ECore
public import EMFBase
public import MultiLevel

/// The names of the deep services of AQL.
public enum AQLMultiLevelServiceName {
    /// `o.ontologicalType()`: the class of the ontological type of an object (MetaDepth
    /// `^type`).
    public static let ontologicalType = "ontologicalType"

    /// `o.linguisticType()`: `Node` or `Edge`.
    public static let linguisticType = "linguisticType"

    /// `o.clabjectName()`: the name of the clabject of an object (MetaDepth `^name`).
    public static let clabjectName = "clabjectName"

    /// `o.level()`: the level of an object.
    public static let level = "level"

    /// `o.potency()`: the potency of an object, a number or `*`.
    public static let potency = "potency"

    /// `o.isDeepInstanceOf(T)`: whether an object is a direct or indirect instance of a type.
    public static let isDeepInstanceOf = "isDeepInstanceOf"

    /// `o.deepTypes()`: the classes of the deep types of an object, nearest first.
    public static let deepTypes = "deepTypes"

    /// `T.deepInstances()`: the direct and indirect instances of a type at every level.
    public static let deepInstances = "deepInstances"

    /// `T.instancesAtLevel(n)`: the direct and indirect instances of a type at a level.
    public static let instancesAtLevel = "instancesAtLevel"

    /// `o.typeAtLevel(n)`: the object that stands for the ontological type of an object at
    /// a level, whose slots can be read.
    public static let typeAtLevel = "typeAtLevel"

    /// `o.slotValue('f')`: the value of a feature, looked up along the type chain.
    public static let slotValue = "slotValue"
}

/// Deep services for the objects of deep level views.
///
/// The services answer questions that the views answer only implicitly: the ontological
/// and linguistic type, level and potency of an object, its deep types, the deep instances
/// of a type at any level, and slot values along the type chain. They apply only to objects
/// that stand for clabjects of the views' model, so other objects keep the standard
/// services. Within a deep level view, `oclIsKindOf` and `allInstances` are already deep.
///
/// ```swift
/// let views = try await model.deepLevelViews(in: ResourceSet())
/// let context = AQLExecutionContext(
///     options: .standard, serviceProviders: [AQLMultiLevelServices(views: views)])
/// ```
public struct AQLMultiLevelServices: AQLServiceProvider {
    /// The views whose objects the services apply to, from the top level down.
    public let views: [DeepLevelView]

    /// Creates the services.
    ///
    /// - Parameter views: The deep level views of one model, typically sharing a resource set.
    public init(views: [DeepLevelView]) {
        self.views = views
    }

    /// The model of the views.
    var model: DeepModel? { views.first?.model }

    /// The view of a level.
    func view(atLevel level: Int) -> DeepLevelView? {
        views.first { $0.level == level }
    }

    /// The clabject that a value stands for, if it is an object of the views.
    func clabject(of value: (any EcoreValue)?) -> Clabject? {
        guard let object = value as? any EObject else { return nil }
        return model?.clabject(object.id)
    }

    /// The class that stands for a clabject in the first view that has one.
    func eClass(of clabject: EUUID) -> EClass? {
        for view in views.reversed() {
            if let eClass = view.eClass(of: clabject) { return eClass }
        }
        return nil
    }

    /// The object that stands for a clabject in the view of its level.
    func object(of clabject: EUUID) async -> (any EObject)? {
        guard let level = model?.level(of: clabject), let view = view(atLevel: level) else { return nil }
        return await view.resource.resolve(clabject)
    }

    /// The clabjects named like a type.
    func clabjects(named descriptor: AQLTypeDescriptor) -> [Clabject] {
        model?.allClabjects.filter { $0.name == descriptor.typeName } ?? []
    }

    /// The objects of the deep instances of a type, optionally at one level.
    func deepInstances(of descriptor: AQLTypeDescriptor, atLevel level: Int?) async -> EcoreValueArray {
        guard let model else { return EcoreValueArray([]) }
        var objects: [any EcoreValue] = []
        for type in clabjects(named: descriptor) {
            for instance in model.instances(of: type.id, atLevel: level) {
                if let object = await object(of: instance.id) { objects.append(object) }
            }
        }
        return EcoreValueArray(objects)
    }

    /// The Ecore value of slot values.
    func ecoreValue(_ values: [DeepValue]) async -> (any EcoreValue)? {
        var converted: [any EcoreValue] = []
        for value in values {
            switch value {
            case .string(let text), .literal(let text): converted.append(text)
            case .integer(let number): converted.append(number)
            case .real(let number): converted.append(number)
            case .boolean(let flag): converted.append(flag)
            case .object(let id):
                if let object = await object(of: id) { converted.append(object) }
            }
        }
        return converted.count == 1 ? converted[0] : EcoreValueArray(converted)
    }

    /// The services offered.
    public var services: [AQLService] {
        let isClabject: AQLReceiver = .custom { [self] value in clabject(of: value) != nil }
        return [
            AQLService(AQLMultiLevelServiceName.ontologicalType, receiver: isClabject) { [self] call in
                clabject(of: call.receiver)?.type.flatMap(eClass(of:))
            },
            AQLService(AQLMultiLevelServiceName.linguisticType, receiver: isClabject) { [self] call in
                clabject(of: call.receiver).map { $0.isEdge ? MultiLevelSyntax.edgeKeyword : MultiLevelSyntax.nodeKeyword }
            },
            AQLService(AQLMultiLevelServiceName.clabjectName, receiver: isClabject) { [self] call in
                clabject(of: call.receiver)?.name
            },
            AQLService(AQLMultiLevelServiceName.level, receiver: isClabject) { [self] call in
                clabject(of: call.receiver).flatMap { model?.level(of: $0.id) }
            },
            AQLService(AQLMultiLevelServiceName.potency, receiver: isClabject) { [self] call in
                guard let clabject = clabject(of: call.receiver), let potency = model?.potency(of: clabject.id) else {
                    return nil
                }
                return potency.finiteValue.map { $0 as any EcoreValue } ?? potency.description
            },
            AQLService(
                AQLMultiLevelServiceName.isDeepInstanceOf, receiver: isClabject, arity: 1, acceptsTypeArguments: true
            ) { [self] call in
                let descriptor = try call.type(0)
                guard let clabject = clabject(of: call.receiver), let model else { return false }
                return model.deepTypes(of: clabject.id).contains { $0.name == descriptor.typeName }
            },
            AQLService(AQLMultiLevelServiceName.deepTypes, receiver: isClabject) { [self] call in
                guard let clabject = clabject(of: call.receiver), let model else { return nil }
                return EcoreValueArray(model.deepTypes(of: clabject.id).compactMap { eClass(of: $0.id) }, kind: .sequence)
            },
            AQLService(AQLMultiLevelServiceName.deepInstances, receiver: .type) { [self] call in
                guard let descriptor = call.receiver as? AQLTypeDescriptor else { return nil }
                return await deepInstances(of: descriptor, atLevel: nil)
            },
            AQLService(AQLMultiLevelServiceName.instancesAtLevel, receiver: .type, arity: 1) { [self] call in
                guard let descriptor = call.receiver as? AQLTypeDescriptor else { return nil }
                return await deepInstances(of: descriptor, atLevel: try call.integer(0))
            },
            AQLService(AQLMultiLevelServiceName.typeAtLevel, receiver: isClabject, arity: 1) { [self] call in
                let level = try call.integer(0)
                guard let clabject = clabject(of: call.receiver), let model,
                    let type = model.ontologicalTypeChain(of: clabject.id).first(where: { model.level(of: $0.id) == level })
                else { return nil }
                return await object(of: type.id)
            },
            AQLService(AQLMultiLevelServiceName.slotValue, receiver: isClabject, arity: 1) { [self] call in
                guard let clabject = clabject(of: call.receiver), let values = model?.values(of: try call.string(0), at: clabject.id)
                else { return nil }
                return await ecoreValue(values)
            },
        ]
    }
}
