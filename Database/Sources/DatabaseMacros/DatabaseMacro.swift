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
        case variableTypeMalFormed(variable: String)
        case relationshipCannotBeCodable
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
        var type: String = ""
        var isCodable: Bool = false
        var declaration: VariableDeclSyntax
    }
    
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        
        let declaration = try Self.validateDeclaration(declaration)
        
        var variables = try Self.getVariables(from: declaration)
        try Self.validateIDExistence(on: variables)
        
        variables = Self.filterOutIgnorables(on: variables)
        variables = Self.getVariableNames(of: variables)
        variables = try Self.findRelationshipsAndTypes(on: variables)
        variables = try Self.findCodables(on: variables)
        
        let entityName = try Self.getEntityName(of: node)
        
        // tem que mudar por causa dos codable da vida
        let valuesDecl = variables.contains(where: \.isOptional) ? "var" : "let"
        
        // Parsing encoding variables
        let encodingPlainValues = Self.parsePlainValuesIntoEncodeStmts(variables: variables)
        let encodingOptionalValues = Self.parsePlainOptionalValuesIntoEncodeStmts(variables: variables)
        
        let toOne = Self.parseToOneRelationshipsIntoEncodeDictStmt(variables: variables)
        let toMany = Self.parseToManyRelationshipsIntoEncodeDictStmt(variables: variables)
        
        // Parsing decoding variables
        let (decodingPlainValues, decodingPlainOptionalValues) = Self.parsePlainValuesIntoDecodeStmts(variables: variables)
        let decodingToOneValues = Self.parseToOneRelationshipsIntoDecodeStmts(variables: variables)
        let decodingToManyValues = Self.parseToManyRelationshipsIntoDecodeStmts(variables: variables)
        
        let entityRepresentableExtension = try ExtensionDeclSyntax("""
        extension \(type.trimmed): EntityRepresentable {
            static func decode(representation: EntityRepresentation, visited: inout [UUID : (any EntityRepresentable)?]) -> Self? {
                if let result = visited[representation.id] {
                    return (result as? Self)
                }
        
                visited.updateValue(nil, forKey: representation.id)
                
                \(raw: decodingPlainValues)
        
                \(raw: decodingPlainOptionalValues)
        
                \(raw: decodingToOneValues)
        
                \(raw: decodingToManyValues)
            }
            
            func encode(visited: inout [UUID : EntityRepresentation]) -> EntityRepresentation {
                if let encoded = visited[self.id] {
                    return encoded
                }
        
                let encoded = EntityRepresentation(id: self.id, entityName: "\(raw: entityName)", values: [:], toOneRelationships: [:], toManyRelationships: [:])
                visited[self.id] = encoded
        
                \(raw: valuesDecl) values: [String : Any] = [
                    \(raw: encodingPlainValues)
                ]
                \(encodingOptionalValues.isEmpty ? "" : "\n\(encodingOptionalValues)\n")
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
    private static func parsePlainOptionalValuesIntoEncodeStmts(variables: [VariableDetails]) -> String {
        let result = variables
            .filter({ $0.isOptional && $0.relationship == .none && !$0.isCodable })
            .map { variable in
                let variableName = variable.customName != nil ? variable.customName! : variable.trueName
                
                let result = """
                if self.\(variable.trueName) != nil {
                    values["\(variableName)"] = self.\(variable.trueName)!
                }
                """
                
                return result
            }
            .joined(separator: "\n\n")
        
        return result
    }
    
    private static func parsePlainValuesIntoEncodeStmts(variables: [VariableDetails]) -> String {
        let result = variables
            .filter({ !$0.isOptional && $0.relationship == .none && !$0.isCodable })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName ?? variable.trueName
                
                newResult.append("""
                "\(variableName)" : self.\(variable.trueName),
                """)
                
                return newResult
            }
        
        if result.isEmpty {
            return ":"
        }
        
        return result.joined(separator: "\n")
    }
    
    private static func parseToOneRelationshipsIntoEncodeDictStmt(variables: [VariableDetails]) -> String {
        let result = variables
            .filter({ $0.relationship == .toOne })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName ?? variable.trueName
                
                newResult.append("""
                "\(variableName)" : self.\(variable.trueName).encode(visited: &visited),
                """)
                
                return newResult
            }
        
        return result.isEmpty ? ":" : result.joined(separator: "\n")
    }
    
    private static func parseToManyRelationshipsIntoEncodeDictStmt(variables: [VariableDetails]) -> String {
        let toMany = variables
            .filter({ $0.relationship == .toMany })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName != nil ? variable.customName! : variable.trueName
                
                newResult.append("""
                "\(variableName)" : self.\(variable.trueName).map({ $0.encode(visited: &visited) }),
                """)
                
                return newResult
            }
        
        
        return toMany.isEmpty ? ":" : toMany.joined(separator: "\n")
    }
}

// MARK: - Main Macro Decode Parsers
extension EntityRepresentableMacro {
    private static func parsePlainValuesIntoDecodeStmts(variables: [VariableDetails]) -> (plain: String, optionals: String) {
        let mandatoryValues = variables
            .filter({ !$0.isOptional && $0.relationship == .none && !$0.isCodable })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName ?? variable.trueName
                
                newResult.append("""
                guard let \(variableName) = representation.values["\(variableName)"] as? \(variable.type) else { return nil }
                """)
                
                return newResult
            }
        
        let optionalValues = variables
            .filter({ $0.isOptional && $0.relationship == .none && !$0.isCodable })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName ?? variable.trueName
                
                newResult.append("""
                let \(variableName) = representation.values["\(variableName)"] as? \(variable.type)
                """)
                
                return newResult
            }
        
        return (mandatoryValues.joined(separator: "\n\n"), optionalValues.joined(separator: "\n"))
    }
    
    private static func parseToOneRelationshipsIntoDecodeStmts(variables: [VariableDetails]) -> String {
        let toOne = variables
            .filter({ $0.relationship == .toOne })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName ?? variable.trueName
                
                newResult.append("""
                guard let \(variableName)Representation = representation.toOneRelationships["\(variableName)"], let \(variableName) = \(variable.type).decode(representation: \(variableName)Representation, visited: &visited) else { return nil }
                """)
                
                return newResult
            }
        
        return toOne.joined(separator: "\n")
    }
    
    private static func parseToManyRelationshipsIntoDecodeStmts(variables: [VariableDetails]) -> String {
        let toMany = variables
            .filter({ $0.relationship == .toMany })
            .reduce([String]()) { partialResult, variable in
                var newResult = partialResult
                let variableName = variable.customName ?? variable.trueName
                
                newResult.append("""
                guard let \(variableName)Representations = representation.toManyRelationships["\(variableName)"] else { return nil }
                let \(variableName) = \(variableName)Representations.reduce(\(variable.type)()) { partialResult, innerRepresentation in
                    guard let model = \(variable.type).decode(representation: innerRepresentation, visited: &visited) else {
                        return partialResult
                    }
                    
                    var result = partialResult
                    result.append(model)
                
                    return result
                }
                
                """)
                
                return newResult
            }
        return toMany.joined(separator: "\n")
    }
    
    private static func parseCodableValuesIntoDecodeStmts(variables: [VariableDetails]) -> String {
        
        return ""
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
    
    private static func findRelationshipsAndTypes(on variables: [VariableDetails]) throws -> [VariableDetails] {
        try variables
            .map { variable in
                let isRelationship = variable.declaration.attributes
                    .compactMap({ $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) })
                    .filter({ $0.name.text == "EntityRepresentableRelationship" })
                    .map(\.name.text)
                    .count == 1
                
                let arrayType = variable.declaration.bindings.first?.typeAnnotation?.type.as(ArrayTypeSyntax.self)
                if let arrayType = arrayType {
                    // TODO: Fix this. It will break if it is an array with optional values inside it.
                    guard var type = arrayType.element.as(IdentifierTypeSyntax.self)?.name.text else {
                        throw EntityRepresentableError.variableTypeMalFormed(variable: variable.trueName)
                    }
                    
                    type = "[\(type)]"
                    
                    if isRelationship {
                        return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .toMany, type: type, declaration: variable.declaration)
                    }
                    
                    return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .none, type: type, declaration: variable.declaration)
                }
                
                let optionalType = variable.declaration.bindings.first?.typeAnnotation?.type.as(OptionalTypeSyntax.self)
                if let optionalType = optionalType {
                    if var type = optionalType.wrappedType.as(ArrayTypeSyntax.self)?.element.as(IdentifierTypeSyntax.self)?.name.text {
                        type = "[\(type)]"
                        if isRelationship {
                            return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .toMany, isOptional: true, type: type, declaration: variable.declaration)
                        }
                        
                        return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .none, isOptional: true, type: type, declaration: variable.declaration)
                    }
                    
                    guard let type = optionalType.wrappedType.as(IdentifierTypeSyntax.self)?.name.text else {
                        throw EntityRepresentableError.variableTypeMalFormed(variable: variable.trueName)
                    }
                    
                    if isRelationship {
                        return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .toOne, isOptional: true, type: type, declaration: variable.declaration)
                    }
                    
                    return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .none, isOptional: true, type: type, declaration: variable.declaration)
                }
                
                let pureType = variable.declaration.bindings.first?.typeAnnotation?.type.as(IdentifierTypeSyntax.self)
                if let pureType = pureType {
                    let type = pureType.name.text
                    
                    if isRelationship {
                        return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .toOne, type: type, declaration: variable.declaration)
                    }
                    
                    return VariableDetails(trueName: variable.trueName, customName: variable.customName, relationship: .none, type: type, declaration: variable.declaration)
                }

                throw EntityRepresentableError.variableTypeMalFormed(variable: variable.trueName)
            }
    }
    
    private static func findCodables(on variables: [VariableDetails]) throws -> [VariableDetails] {
        let variables = try variables.map { variable in
            let attributes = variable
                .declaration.attributes
                .compactMap({ $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) })
            
            let isCodable = !attributes
                .filter({ $0.name.text == "EntityRepresentableCodable" })
                .isEmpty
            
            if !isCodable { return variable }
            
            let isRelationship = !attributes
                .filter({ $0.name.text == "EntityRepresentableRelationship" })
                .isEmpty
            
            if isRelationship {
                throw EntityRepresentableError.relationshipCannotBeCodable
            }
            
            var newVariable = variable
            newVariable.isCodable = true
            
            return newVariable
        }
        
        return variables
    }
    
    private static func filterOutIgnorables(on variables: [VariableDetails]) -> [VariableDetails] {
        variables
            .filter { variable in
                variable.declaration.attributes
                    .compactMap({ $0.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self) })
                    .filter({ $0.name.text == "EntityRepresentableIgnorable" })
                    .isEmpty
            }
    }
    
    private static func getVariableNames(of variables: [VariableDetails]) -> [VariableDetails] {
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

public struct EntityRepresentableCodableMacro: MemberAttributeMacro {
    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingAttributesFor member: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [AttributeSyntax] {
        return []
    }
}

@main
struct DatabasePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        EntityRepresentableMacro.self,
        EntityRepresentableRelationshipMacro.self,
        EntityRepresentableIgnorableMacro.self,
        EntityRepresentableCodableMacro.self
    ]
}
