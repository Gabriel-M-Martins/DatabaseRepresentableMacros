import Database
import Foundation

class Category {
    var id: UUID
    var name: String
//    var clothes: [Clothing]
    
    required init(id: UUID = UUID(), name: String = "Default"/*, clothes: [Clothing] = []*/) {
        self.id = id
        self.name = name
//        self.clothes = clothes
    }
}

extension Category: EntityRepresentable {
    static func decode(representation: Database.EntityRepresentation, visited: inout [UUID : (any Database.EntityRepresentable)?]) -> Self? {
        guard let name = representation.values["name"] as? String,
              let clothesRepresentations = representation.toManyRelationships["clothes"] else { return nil }
        
//        let clothes = clothesRepresentations.reduce([Clothing]()) { partialResult, innerRepresentation in
//            guard let model = Clothing.decode(representation: innerRepresentation, visited: &visited) else { return partialResult }
//            
//            var result = partialResult
//            result.append(model)
//            
//            return result
//        }
        
        let decoded = Self.init(id: representation.id, name: name)
        visited[representation.id] = decoded
        
        return decoded
    }
    
    func encode(visited: inout [UUID : Database.EntityRepresentation]) -> Database.EntityRepresentation {
        if let encoded = visited[self.id] {
            return encoded
        }
        
        let encoded = EntityRepresentation(id: self.id, entityName: "CategoryEntity", values: [:], toOneRelationships: [:], toManyRelationships: [:])
        visited[self.id] = encoded
        
        let values: [String : Any] = [
            "id" : self.id,
            "name" : self.name
        ]
        
        let toOneRelationships: [String : EntityRepresentation] = [:]
        
        let toManyRelationships: [String : [EntityRepresentation]] = [
            :
//            "clothes" : self.clothes.map({ $0.encode(visited: &visited) })
        ]
        
        encoded.values = values
        encoded.toOneRelationships = toOneRelationships
        encoded.toManyRelationships = toManyRelationships
        
        return encoded
    }
}



//@EntityRepresentable(entityName: "ClothingEntity")
//class Clothing {
//    var id: UUID = UUID()
//    var valor: String = ""
//    
//    @EntityRepresentableRelationship
//    var category: [Category] = []
//}
