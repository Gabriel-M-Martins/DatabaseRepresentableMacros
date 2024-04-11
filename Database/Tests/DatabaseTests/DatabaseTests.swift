import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import Database

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(DatabaseMacros)
import DatabaseMacros

let testMacros: [String: Macro.Type] = [
    "EntityRepresentable": EntityRepresentableMacro.self,
    "EntityRepresentableRelationship": EntityRepresentableRelationshipMacro.self,
    "EntityRepresentableIgnorable" : EntityRepresentableIgnorableMacro.self,
    "EntityRepresentableCustomNamed" : EntityRepresentableCustomNamedMacro.self,
    "EntityRepresentableCodable" : EntityRepresentableCodableMacro.self
]
#endif

final class DatabaseTests: XCTestCase {
    func testMacro() throws {
        #if canImport(DatabaseMacros)
        assertMacroExpansion(
            """
            @EntityRepresentable(entityName: "ClothingEntity")
            class Clothing {
                var id: UUID
                var valor: String
                @EntityRepresentableRelationship
                @EntityRepresentableCustomNamed("barril")
                var bar: Foo
                @EntityRepresentableRelationship
                var bar3: Foo
                @EntityRepresentableRelationship
                var bar2: [Foo]
                @EntityRepresentableIgnorable
                var ignored = ""
                var optionalValue: String?
                @EntityRepresentableCodable
                var casoDoEnum: EnumDeAlgo
                @EntityRepresentableCodable
                var casoOpcionalDoEnum: EnumDeAlgo?
            }
            """,
            expandedSource: """
            class Clothing {
                var id: UUID
                var valor: String
                var bar: Foo
                var bar3: Foo
                var bar2: [Foo]
                var ignored = ""
                var optionalValue: String?
                var casoDoEnum: EnumDeAlgo
                var casoOpcionalDoEnum: EnumDeAlgo?
            }
            
            extension Clothing: EntityRepresentable {
                static func decode(representation: EntityRepresentation, visited: inout [UUID : (any EntityRepresentable)?]) -> Self? {
                    if let result = visited[representation.id] {
                        return (result as? Self)
                    }
            
                    visited.updateValue(nil, forKey: representation.id)
            
                    guard let id = representation.values["id"] as? UUID else {
                        return nil
                    }
            
                    guard let valor = representation.values["valor"] as? String else {
                        return nil
                    }
            
                    let optionalValue = representation.values["optionalValue"] as? String
            
                    guard let barrilRepresentation = representation.toOneRelationships["barril"], let barril = Foo.decode(representation: barrilRepresentation, visited: &visited) else {
                        return nil
                    }
                    guard let bar3Representation = representation.toOneRelationships["bar3"], let bar3 = Foo.decode(representation: bar3Representation, visited: &visited) else {
                        return nil
                    }
            
                    guard let bar2Representations = representation.toManyRelationships["bar2"] else {
                        return nil
                    }
                    let bar2 = bar2Representations.reduce([Foo] ()) { partialResult, innerRepresentation in
                        guard let model = [Foo].decode(representation: innerRepresentation, visited: &visited) else {
                            return partialResult
                        }

                        var result = partialResult
                        result.append(model)

                        return result
                    }
            
                }
            
                func encode(visited: inout [UUID : EntityRepresentation]) -> EntityRepresentation {
                    if let encoded = visited[self.id] {
                        return encoded
                    }
            
                    let encoded = EntityRepresentation(id: self.id, entityName: "ClothingEntity", values: [:], toOneRelationships: [:], toManyRelationships: [:])
                    visited[self.id] = encoded
            
                    var values: [String : Any] = [
                        "id" : self.id,
                        "valor" : self.valor,
                    ]
            
                    if self.optionalValue != nil {
                        values["optionalValue"] = self.optionalValue!
                    }
            
                    let toOneRelationships: [String : EntityRepresentation] = [
                        "barril" : self.bar.encode(visited: &visited),
                        "bar3" : self.bar3.encode(visited: &visited),
                    ]
            
                    let toManyRelationships: [String : [EntityRepresentation]] = [
                        "bar2" : self.bar2.map({
                                    $0.encode(visited: &visited)
                                }),
                    ]
            
                    encoded.values = values
                    encoded.toOneRelationships = toOneRelationships
                    encoded.toManyRelationships = toManyRelationships
            
                    return encoded
                }
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform.")
        #endif
    }
}
