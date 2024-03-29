//
//  EntityRepresentable.swift
//  Database
//
//  Created by Gabriel Medeiros Martins on 25/03/24.
//

import Foundation

/// Structs that are going to be stored in a database should implement this protocol to proper map the communication with *any* database.
public protocol EntityRepresentable: Equatable, Hashable, AnyObject {
    var id: UUID { get set }
    static func decode(representation: EntityRepresentation, visited: inout [UUID : (any EntityRepresentable)?]) -> Self?
    func encode(visited: inout [UUID : EntityRepresentation]) -> EntityRepresentation
}

public extension EntityRepresentable {
    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self)
    }
}
