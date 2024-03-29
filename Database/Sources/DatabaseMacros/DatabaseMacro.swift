import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct EntityRepresentableMacro: ExtensionMacro {
    public enum EntityRepresentableError: Error {
        case declarationIsntClass
        case mustHaveOneArgument(numberOfArgumentsProvided: Int)
        case entityNameIsntString
        case entityTypeIsntValid
        case classDoesntHaveProperties
        case classDoesntHaveIDProperty
    }
    
    private enum Relationship {
        case toOne
        case toMany
        case none
    }
    
    private struct VariableDetails {
        var trueName: String = ""
        var customName: String? = nil
        var relationship: Relationship = .none
        var isOptional: Bool = false
        var declaration: VariableDeclSyntax
    }
    
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        
        let declaration = try Self.validateDeclaration(declaration)
        
        var variables = try Self.getVariables(from: declaration)
        try Self.validateIDExistence(on: variables)
        
        variables = try Self.filterOutIgnorables(on: variables)
        let findOptionals = try Self.findOptionals(on: variables)
        let hasOptionals = findOptionals.hasOptionals
        variables = findOptionals.variables

        variables = try Self.findRelationships(on: variables)
        variables = try Self.getVariableNames(of: variables)
        
        let entityName = try Self.getEntityName(of: node)
        
        // Parsing variables for Encode
        let values = Self.parseValuesIntoDictString(variables: variables)
        let (toOne, toMany) = Self.parseRelationshipsIntoDictString(variables: variables)
        
        let entityRepresentableExtension = try ExtensionDeclSyntax("""
        extension \(type.trimmed): EntityRepresentable {
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
        
                let encoded = EntityRepresentation(id: self.id, entityName: "\(raw: entityName)", values: [:], toOneRelationships: [:], toManyRelationships: [:])
                visited[self.id] = encoded
        
                let values: [String : Any] = [
                    \(raw: values)
                ]
        
                let toOneRelationships: [String : EntityRepresentation] = [
                    \(raw: toOne)
                ]
        
                let toManyRelationships: [String : [EntityRepresentation]] = [
                    \(raw: toMany)
                ]
        
                encoded.values = values
                encoded.toOneRelationships = toOneRelationships
                encoded.toManyRelationships = toManyRelationships
        
                return encoded
            }
        }
        """)
        
        return [
            entityRepresentableExtension
        ]
    }
}


// MARK: - Main Macro Encode Parsers
extension EntityRepresentableMacro {
    private static func parseValuesIntoDictString(variables: [VariableDetails]) -> String {
        let parsedStrings = variables
            .reduce([String]()) { partialResult, variable in
                guard variable.relationship == .none else { return partialResult }
                
                var newResult = partialResult
                let variableName = variable.customName != nil ? variable.customName! : variable.trueName
                
                newResult.append("""
                "\(variableName)" : self.\(variable.trueName),
                """)
                
                return newResult
            }
        
        if parsedStrings.isEmpty {
            return ":"
        }
        
        return parsedStrings.joined(separator: "\n")
    }
    
    private static func parseRelationshipsIntoDictString(variables: [VariableDetails]) -> (toOne: String, toMany: String) {
        let toOne = variables
            .reduce([String]()) { partialResult, variable in
                guard variable.relationship == .toOne else { return partialResult }
                
                var newResult = partialResult
                let variableName = variable.customName != nil ? variable.customName! : variable.trueName
                
                newResult.append("""
                "\(variableName)" : self.\(variable.trueName).encode(visited: &visited),
                """)
                
                return newResult
            }
        
        let toMany = variables
            .reduce([String]()) { partialResult, variable in
                guard variable.relationship == .toMany else { return partialResult }
                
                var newResult = partialResult
                let variableName = variable.customName != nil ? variable.customName! : variable.trueName
                
                newResult.append("""
                "\(variableName)" : self.\(variable.trueName).map({ $0.encode(visited: &visited) }),
                """)
                
                return newResult
            }
        
        
        return (toOne: toOne.isEmpty ? ":" : toOne.joined(separator: "\n"),
                toMany: toMany.isEmpty ? ":" : toMany.joined(separator: "\n"))
    }
}

// MARK: - Main Macro Utilities
extension EntityRepresentableMacro {
    private static func validateDeclaration(_ declaration: some DeclGroupSyntax) throws -> ClassDeclSyntax {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw EntityRepresentableError.declarationIsntClass
        }
        
        return classDecl
    }
    
    private static func getEntityName(of node: AttributeSyntax) throws -> String {
        guard let argumentList = node.arguments else {
            throw EntityRepresentableError.mustHaveOneArgument(numberOfArgumentsProvided: 0)
        }
        
        let arguments = argumentList
            .children(viewMode: .sourceAccurate)
            .compactMap({ $0.as(LabeledExprSyntax.self) })
        
        if arguments.count != 1 {
            throw EntityRepresentableError.mustHaveOneArgument(numberOfArgumentsProvided: arguments.count)
        }
        
        guard let entityName = arguments[0].expression.as(StringLiteralExprSyntax.self)?.segments else {
            throw EntityRepresentableError.entityNameIsntString
        }
        
        return "\(entityName)"
    }
    
    private static func getVariables(from declaration: ClassDeclSyntax) throws -> [VariableDetails] {
        let members = declaration.memberBlock.members
        
        let variables = members
            .compactMap({ $0.decl.as(VariableDeclSyntax.self) })
        
        guard !variables.isEmpty else {
            throw EntityRepresentableError.classDoesntHaveProperties
        }
        
        return variables
            .map({ VariableDetails(declaration: $0) })
    }
    
    private static func validateIDExistence(on variables: [VariableDetails]) throws {
        let idExists = variables
            .filter { variable in
                // TODO: fazer passar por toda a lista de bindings
                guard variable.declaration.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "id" else {
                    return false
                }
                
                // TODO: fazer passar por toda a lista de bindings
                guard variable.declaration.bindings.first?.typeAnnotation?.type.as(IdentifierTypeSyntax.self)?.name.text == "UUID" else {
                    return false
                }
                
                return true
            }
            .count == 1
        
        guard idExists else {
            throw EntityRepresentableError.classDoesntHaveIDProperty
        }
    }
    
    private static func findRelationships(on variables: [VariableDetails]) throws -> [VariableDetails] {
        variables
            .map { variable in
                let isRelationship = variable.declaration.attributes
                    .compactMap({ $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) })
                    .filter({ $0.name.text == "EntityRepresentableRelationship" })
                    .map(\.name.text)
                    .count == 1
                
                if isRelationship {
                    let isArray = variable.declaration.bindings.first?.typeAnnotation?.type.is(ArrayTypeSyntax.self) ?? false
                    
                    if isArray {
                        return VariableDetails(relationship: .toMany, declaration: variable.declaration)
                    }
                    
                    return VariableDetails(relationship: .toOne, declaration: variable.declaration)
                }
                
                return variable
            }
    }
    
    private static func filterOutIgnorables(on variables: [VariableDetails]) throws -> [VariableDetails] {
        return variables
            .filter { variable in
                variable.declaration.attributes
                    .compactMap({ $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) })
                    .filter({ $0.name.text == "EntityRepresentableIgnorable" })
                    .isEmpty
            }
    }
    
    private static func getVariableNames(of variables: [VariableDetails]) throws -> [VariableDetails] {
        variables
            .reduce([VariableDetails]()) { partialResult, variable in
                let customNamedAttribute = variable.declaration.attributes
                    .compactMap({ $0.as(AttributeSyntax.self) })
                    .filter { attribute in
                        if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
                            return identifier == "EntityRepresentableCustomNamed"
                        }
                        
                        return false
                    }
                    .last
                
                
                guard let trueName = variable.declaration.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    return partialResult
                }
                
                let customName = customNamedAttribute?
                    .arguments?
                    .as(LabeledExprListSyntax.self)?.first?
                    .expression
                    .as(StringLiteralExprSyntax.self)?.segments
                
                var newResult = partialResult
                newResult.append(VariableDetails(trueName: "\(trueName)", customName: customName != nil ? "\(customName!)" : nil, relationship: variable.relationship, declaration: variable.declaration))
                
                return newResult
            }
    }
    
    private static func findOptionals(on variables: [VariableDetails]) throws -> (variables: [VariableDetails], hasOptionals: Bool) {
        var hasOptionalValues = false
        
        let variables = variables
            .map { variable in
                let isOptional = variable
                    .declaration
                    .bindings
                    .compactMap({ $0.typeAnnotation?.type.as(OptionalTypeSyntax.self) })
                    .count > 0
                
                if isOptional && !hasOptionalValues {
                    hasOptionalValues = true
                }
                
                return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: variable.relationship, isOptional: isOptional, declaration: variable.declaration)
            }
        
        return (variables, hasOptionalValues)
    }
}


// MARK: - Auxiliar Macros-

public struct EntityRepresentableRelationshipMacro: MemberAttributeMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingAttributesFor member: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.AttributeSyntax] {
        return []
    }
}

public struct EntityRepresentableIgnorableMacro: MemberAttributeMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingAttributesFor member: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.AttributeSyntax] {
        return []
    }
}

public struct EntityRepresentableCustomNamedMacro: MemberAttributeMacro {
    public static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingAttributesFor member: some SwiftSyntax.DeclSyntaxProtocol, in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.AttributeSyntax] {
        return []
    }
}

@main
struct DatabasePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EntityRepresentableMacro.self,
        EntityRepresentableRelationshipMacro.self,
        EntityRepresentableIgnorableMacro.self
    ]
}
