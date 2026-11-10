//
//  OCLMetamodelSummary.swift
//  AQLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase

/// Renders the structure of packages as text, so that tests can compare packages without
/// regard to identifiers.
enum OCLMetamodelSummary {
    static func describe(_ packages: [EPackage]) -> String {
        var references: [EUUID: String] = [:]
        var attributes: [EUUID: String] = [:]
        func index(_ package: EPackage) {
            for case let eClass as EClass in package.eClassifiers {
                for feature in eClass.eStructuralFeatures {
                    if let reference = feature as? EReference { references[reference.id] = eClass.name + "." + reference.name }
                    if let attribute = feature as? EAttribute { attributes[attribute.id] = attribute.name }
                }
            }
            package.eSubpackages.forEach(index)
        }
        packages.forEach(index)
        var lines: [String] = []
        func annotations(_ element: some EModelElement, _ indent: String) {
            for annotation in element.eAnnotations {
                lines.append(indent + "@" + annotation.source + " " + annotation.details.map { "\($0.key)=\($0.value)" }.joined(separator: "|"))
            }
        }
        func describe(_ package: EPackage, _ indent: String) {
            lines.append(indent + "package \(package.name) \(package.nsPrefix) \(package.nsURI)")
            annotations(package, indent + "  ")
            for classifier in package.eClassifiers {
                switch classifier {
                case let eClass as EClass:
                    lines.append(indent + "  class \(eClass.name) abstract=\(eClass.isAbstract) interface=\(eClass.isInterface) super=\(eClass.eSuperTypes.map(\.name)) instance=\(eClass.instanceClassName ?? "-")")
                    annotations(eClass, indent + "    ")
                    for feature in eClass.eStructuralFeatures {
                        if let a = feature as? EAttribute {
                            lines.append(indent + "    attribute \(a.name):\(a.eType.name)[\(a.lowerBound)..\(a.upperBound)] o=\(a.ordered) u=\(a.unique) c=\(a.changeable) v=\(a.volatile) t=\(a.transient) d=\(a.derived) id=\(a.isID) us=\(a.unsettable) default=\(a.defaultValueLiteral ?? "-")")
                            annotations(a, indent + "      ")
                        }
                        if let r = feature as? EReference {
                            lines.append(indent + "    reference \(r.name):\(r.eType.name)[\(r.lowerBound)..\(r.upperBound)] o=\(r.ordered) u=\(r.unique) c=\(r.changeable) v=\(r.volatile) t=\(r.transient) d=\(r.derived) us=\(r.unsettable) contains=\(r.containment) resolve=\(r.resolveProxies) opposite=\(r.opposite.flatMap { references[$0] } ?? "-") keys=\(r.eKeys.compactMap { attributes[$0] })")
                            annotations(r, indent + "      ")
                        }
                    }
                    for operation in eClass.eOperations {
                        lines.append(indent + "    operation \(operation.name)(\(operation.eParameters.map { "\($0.name):\($0.eType?.name ?? "-")[\($0.lowerBound)..\($0.upperBound)]" }.joined(separator: ","))):\(operation.eType?.name ?? "-")[\(operation.lowerBound)..\(operation.upperBound)] o=\(operation.ordered) u=\(operation.unique)")
                        annotations(operation, indent + "      ")
                    }
                case let eEnum as EEnum:
                    lines.append(indent + "  enum \(eEnum.name) serialisable=\(eEnum.serialisable) " + eEnum.literals.map { "\($0.name)=\($0.value):\($0.literal ?? "-")" }.joined(separator: ","))
                    annotations(eEnum, indent + "    ")
                case let dataType as EDataType:
                    lines.append(indent + "  datatype \(dataType.name) serialisable=\(dataType.serialisable) instance=\(dataType.instanceClassName ?? "-")")
                    annotations(dataType, indent + "    ")
                default:
                    break
                }
            }
            for subpackage in package.eSubpackages { describe(subpackage, indent + "  ") }
        }
        packages.forEach { describe($0, "") }
        return lines.joined(separator: "\n")
    }
}
