//
//  AQLNumberServices.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// Services available on integers and reals.
///
/// Provides `abs`, `min(other)`, `max(other)`, `floor`, `ceil`, `round`, `div(other)` and
/// `mod(other)`. Standalone calls such as `min(a, b)` reach these services through the
/// dispatcher's receiver rule. Operations on two integers stay integral; mixed operands
/// produce reals.
public struct AQLNumberServices: AQLServiceProvider {
    /// Creates the provider.
    public init() {}

    private static func pick(
        _ call: AQLServiceCall, _ chooseFirst: @Sendable (ComparisonResult) -> Bool
    ) throws -> (any EcoreValue)? {
        guard let other = call.argument(0), AQLValues.isNumber(other),
            let ordering = AQLValues.compare(call.receiver, other)
        else {
            throw AQLExecutionError.typeError("\(call.name) requires numeric arguments")
        }
        if AQLValues.integer(call.receiver) != nil && AQLValues.integer(other) != nil {
            return chooseFirst(ordering) ? call.receiver : other
        }
        return chooseFirst(ordering) ? AQLValues.numericValue(call.receiver) : AQLValues.numericValue(other)
    }

    private static func integerOperation(
        _ call: AQLServiceCall, _ operation: @Sendable (Int, Int) -> Int
    ) throws -> (any EcoreValue)? {
        guard let left = AQLValues.integer(call.receiver), let right = AQLValues.integer(call.argument(0)),
            right != 0
        else {
            throw AQLExecutionError.invalidOperation("\(call.name) requires non-zero integer operands")
        }
        return operation(left, right)
    }

    /// The services offered.
    public var services: [AQLService] {
        [
            AQLService("abs", receiver: .number) { call in
                if let value = AQLValues.integer(call.receiver) { return abs(value) }
                return abs(AQLValues.numericValue(call.receiver) ?? 0)
            },
            AQLService("min", receiver: .number, arity: 1) { try Self.pick($0) { $0 != .orderedDescending } },
            AQLService("max", receiver: .number, arity: 1) { try Self.pick($0) { $0 != .orderedAscending } },
            AQLService("floor", receiver: .number) { call in
                AQLValues.integer(call.receiver) ?? Int((AQLValues.numericValue(call.receiver) ?? 0).rounded(.down))
            },
            AQLService("ceil", receiver: .number) { call in
                AQLValues.integer(call.receiver) ?? Int((AQLValues.numericValue(call.receiver) ?? 0).rounded(.up))
            },
            AQLService("round", receiver: .number) { call in
                AQLValues.integer(call.receiver)
                    ?? Int((AQLValues.numericValue(call.receiver) ?? 0).rounded(.toNearestOrAwayFromZero))
            },
            AQLService("div", receiver: .number, arity: 1) { try Self.integerOperation($0) { $0 / $1 } },
            AQLService("mod", receiver: .number, arity: 1) { try Self.integerOperation($0) { $0 % $1 } },
        ]
    }
}
