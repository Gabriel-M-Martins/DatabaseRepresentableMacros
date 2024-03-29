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
    "EntityRepresentableCustomNamed" : EntityRepresentableCustomNamedMacro.self
]
#endif

final class DatabaseTests: XCTestCase {
    func testMacro() throws {
        #if canImport(DatabaseMacros)
        assertMacroExpansion(
            """
            class Foo {}
            extension Foo: EntityRepresentable {}
            @EntityRepresentable(entityName: "ClothingEntity")
            class Clothing {
                var id: UUID
                var valor: String
                @EntityRepresentableRelationship
                @EntityRepresentableCustomNamed("barril")
                var bar: Foo
                @EntityRepresentableRelationship
                var bar2: [Foo]
                @EntityRepresentableIgnorable
                var ignored = ""
                @EntityRepresentableCustomNamed("thatsOpt")
                var valorOptional: String? = nil
                var arrayOptional: [String]? = nil
            }
            """,
            expandedSource: """
            class Foo {}
            extension Foo: EntityRepresentable {}
            class Clothing {
                var id: UUID
                var valor: String
                var bar: Foo
                var bar2: [Foo]
                var ignored = ""
                var valorOptional: String? = nil
                var arrayOptional: [String]? = nil
            }
            
            extension Clothing: EntityRepresentable {
                static func decode(representation: EntityRepresentation, visited: inout [UUID : (any EntityRepresentable)?]) -> Self? {
                    if let result = visited[representation.id] {
                        return (result as? Self)
                    }
            
                    visited.updateValue(nil, forKey: representation.id)
            
                }
            
                func encode(visited: inout [UUID : EntityRepresentation]) -> EntityRepresentation {
                    if let encoded = visited[self.id] {
                        return encoded
                    }
            
                    let encoded = EntityRepresentation(id: self.id, entityName: "ClothingEntity", values: [:], toOneRelationships: [:], toManyRelationships: [:])
                    visited[self.id] = encoded
            
                    let values: [String : Any] = [
                        "id" : self.id,
                        "valor" : self.valor,
                        "thatsOpt" : self.valorOptional,
                    ]
            
                    let toOneRelationships: [String : EntityRepresentation] = [
                        "barril" : self.bar.encode(visited: &visited),
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
