//
//  CoreDataRepository.swift
//  Database
//
//  Created by Gabriel Medeiros Martins on 25/03/24.
//

import Foundation
import CoreData

public final class CoreDataRepository<Model>: Repository where Model: EntityRepresentable {
    private var container: NSPersistentContainer
    
    private var entityName: String
    
    public init(container: NSPersistentContainer, entityName: String) {
        self.container = container
        self.entityName = entityName
    }
    
    public func delete(_ model: Model) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            var visited: [UUID : EntityRepresentation] = [:]
            let representation = model.encode(visited: &visited)
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "id == %@", representation.id as CVarArg)
            
            let fetchedResults = (try? container.viewContext.fetch(request)) ?? []
            
            for result in fetchedResults {
                container.viewContext.delete(result)
            }
            
            try? container.viewContext.save()
        }
    }
    
    private func fetch(_ entityName: String) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return (try? container.viewContext.fetch(request)) ?? []
    }
    
    public func fetch(id: UUID, completion: @escaping (Model) -> ()) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            guard let fetchedResult = (try? container.viewContext.fetch(request))?.first else { return }
            
            var visitedRepresentation: [UUID : EntityRepresentation] = [:]
            guard let representation = traverseRelationships(object: fetchedResult, visited: &visitedRepresentation) else { return }
            
            var visitedModels: [UUID : (any EntityRepresentable)?] = [:]
            if let model = Model.decode(representation: representation, visited: &visitedModels) {
                completion(model)
            }
        }
    }
    
    public func fetch(completion: @escaping  ([Model]) -> ()) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            var visitedRepresentations: [UUID : EntityRepresentation] = [:]
            var visitedModels: [UUID : (any EntityRepresentable)?] = [:]
            var result = [Model]()
            
            let fetchResults = self.fetch(self.entityName)
            for fetchResult in fetchResults {
                guard let representation = traverseRelationships(object: fetchResult, visited: &visitedRepresentations) else { continue }
                
                if let model = Model.decode(representation: representation, visited: &visitedModels) {
                    result.append(model)
                }
            }
            
            completion(result)
        }
    }
    
    public func save(_ model: Model, completion: @escaping (Model?) -> ()) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            var visitedRepresentations: [UUID : EntityRepresentation] = [:]
            var visitedNSManagedObjects: [UUID : NSManagedObject] = [:]
           
            let representation = model.encode(visited: &visitedRepresentations)
            
            guard let entity = self?.traverseRelationships(representation: representation, visited: &visitedNSManagedObjects) else { return }
            
            do {
                try entity.managedObjectContext?.save()
                completion(model)
            } catch {
                completion(nil)
            }
        }
    }
}

extension CoreDataRepository {
    private func representationToEntity(representation: EntityRepresentation, context: NSManagedObjectContext?) -> NSManagedObject? {
        guard let entityDescription = container.managedObjectModel.entitiesByName[representation.entityName] else { return nil }
        
        let existingEntity = fetch(representation.entityName).first(where: { $0.value(forKey: "id") as? UUID == representation.id })
        
        let context = context ?? existingEntity?.managedObjectContext ?? container.viewContext
        let entity = existingEntity ?? NSManagedObject(entity: entityDescription, insertInto: context)

        return entity
    }
    
    private func populateEntity(values: [String : Any], entity: NSManagedObject) {
        for (key, value) in values {
            entity.setValue(value, forKey: key)
        }
    }
    
    private func traverseRelationships(object: NSManagedObject, visited: inout [UUID : EntityRepresentation]) -> EntityRepresentation? {
        guard let id = object.value(forKey: "id") as? UUID,
              let entityName = object.entity.name else { return nil }
        
        if let result = visited[id] {
            return result
        }
        
        let attributes = object.entity.attributesByName.map({ $0.key })
        
        let representation = EntityRepresentation(id: id, entityName: entityName, values: object.dictionaryWithValues(forKeys: attributes), toOneRelationships: [:], toManyRelationships: [:])
        visited[id] = representation
        
        let keysToOneRelationships = object.entity.relationshipsByName.reduce([String]()) { partialResult, item in
            var result = partialResult
            if !item.value.isToMany {
                result.append(item.key)
            }
            return result
        }
        
        var toOneRelationships = [String : EntityRepresentation]()
        for key in keysToOneRelationships {
            guard let relationship = object.value(forKey: key) as? NSManagedObject,
                  let _ = relationship.value(forKey: "id") as? UUID else { continue }
            
            if let representation = traverseRelationships(object: relationship, visited: &visited) {
                visited[representation.id] = representation
                toOneRelationships[key] = representation
                
                continue
            }
        }
        
        representation.toOneRelationships = toOneRelationships
        
        let keysToManyRelationships = object.entity.relationshipsByName.reduce([String]()) { partialResult, item in
            var result = partialResult
            if item.value.isToMany {
                result.append(item.key)
            }
            return result
        }
        
        var toManyRelationships = [String : [EntityRepresentation]]()
        for key in keysToManyRelationships {
            guard let relationships = object.value(forKey: key) as? NSSet else { continue }
                
            var representations = [EntityRepresentation]()
            for relationship in relationships.allObjects as? [NSManagedObject] ?? [] {
                guard let _ = relationship.value(forKey: "id") as? UUID else { continue }
                
                if let representation = traverseRelationships(object: relationship, visited: &visited) {
                    visited[representation.id] = representation
                    representations.append(representation)
                    continue
                }
            }
            
            toManyRelationships[key] = representations
        }
        
        representation.toManyRelationships = toManyRelationships
        
        return representation
    }
    
    private func traverseRelationships(representation: EntityRepresentation, visited: inout [UUID : NSManagedObject], context: NSManagedObjectContext? = nil) -> NSManagedObject? {
        if let result = visited[representation.id] {
            return result
        }
        
        guard let entityParent = representationToEntity(representation: representation, context: context) else { return nil }
        populateEntity(values: representation.values, entity: entityParent)
        
        visited[representation.id] = entityParent
        
        let sonsToOne = representation.toOneRelationships.map { (key: String, value: EntityRepresentation) in
            return (key: key, value: value)
        }
        
        for son in sonsToOne {
            if let entitySon = traverseRelationships(representation: son.value, visited: &visited, context: entityParent.managedObjectContext),
               let relationship = entityParent.entity.relationships(forDestination: entitySon.entity).first(where: { $0.name == son.key }) {
            
                entityParent.setValue(entitySon, forKey: relationship.name)
            }
        }
        
        let sonsToMany = representation.toManyRelationships.map { (key: String, value: [EntityRepresentation]) in
            return (key: key, values: value)
        }
        
        for son in sonsToMany {
            var childrenToAdd = [NSManagedObject]()
            
            for sonK in son.values {
                if let entitySon = traverseRelationships(representation: sonK, visited: &visited, context: entityParent.managedObjectContext) {
                    childrenToAdd.append(entitySon)
                }
            }
            
            if childrenToAdd.isEmpty { continue }
            
            if let relationship = entityParent.entity.relationships(forDestination: childrenToAdd[0].entity).first(where: { $0.name == son.key }) {
                
                entityParent.setValue(NSSet(array: childrenToAdd), forKey: relationship.name)
            }
        }

        return entityParent
    }
}
