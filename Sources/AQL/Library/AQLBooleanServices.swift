//
//  AQLBooleanServices.swift
//  AQL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// Services available on booleans: `not`, `and`, `or`, `xor` and `implies`.
public struct AQLBooleanServices: AQLServiceProvider {
    /// Creates the provider.
    public init() {}

    /// The services offered.
    public var services: [AQLService] {
        let binary: [(String, @Sendable (Bool, Bool) -> Bool)] = [
            ("and", { $0 && $1 }), ("or", { $0 || $1 }), ("xor", { $0 != $1 }),
            ("implies", { !$0 || $1 }),
        ]
        return [
            AQLService("not", receiver: .boolean) { call in
                !(call.receiver as? Bool ?? false)
            }
        ]
            + binary.map { name, operation in
                AQLService(name, receiver: .boolean, arity: 1) { call in
                    guard let left = call.receiver as? Bool, let right = call.argument(0) as? Bool else {
                        return nil
                    }
                    return operation(left, right)
                }
            }
    }
}
