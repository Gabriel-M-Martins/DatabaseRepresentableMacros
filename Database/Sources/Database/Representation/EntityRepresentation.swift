//
//  EntityRepresentation.swift
//  Database
//
//  Created by Gabriel Medeiros Martins on 25/03/24.
//

import Foundation

/// The half-way between the structs used on the app views and business logic and the entities stored on databases.
public class EntityRepresentation {
    /// Shared Id between databases to ensure data consistency.
    public let id: UUID
    /// Name of the entity stored on the databases. All databases used should share the same entity names.
    /// Probably this is going to be modified in the future to be a custom struct that can specify names accordingly to the database.
    /// that is being used.
    public let entityName: String
    /// The properties the entity has. Probably this is going to be modified in the future to be a custom struct that can specify properties
    /// types accordingly to the database.
    public var values: [String : Any] // [String: PrimitiveValue]
    /// This should **only** map to children relationships and **never** to parent relationships as to avoid
    /// infinite mapping loops.
    public var toOneRelationships: [String : EntityRepresentation]
    /// This should **only** map to children relationships and **never** to parent relationships as to avoid
    /// infinite mapping loops.
    public var toManyRelationships: [String : [EntityRepresentation]]
    
    public init(id: UUID, entityName: String, values: [String : Any], toOneRelationships: [String : EntityRepresentation], toManyRelationships: [String : [EntityRepresentation]]) {
        self.id = id
        self.entityName = entityName
        self.values = values
        self.toOneRelationships = toOneRelationships
        self.toManyRelationships = toManyRelationships
    }
}
