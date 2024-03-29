//
//  Repository.swift
//  Database
//
//  Created by Gabriel Medeiros Martins on 25/03/24.
//

import Foundation

public protocol Repository<Model> {
    associatedtype Model where Model: EntityRepresentable
    
    func fetch(completion: @escaping  ([Model]) -> ())
    func fetch(id: UUID, completion: @escaping (Model) -> ())
    func save(_ model: Model, completion: @escaping (Model?) -> ())
    func delete(_ model: Model)
}
