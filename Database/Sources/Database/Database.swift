// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(extension, conformances: EntityRepresentable)
public macro EntityRepresentable(entityName: String) = #externalMacro(module: "DatabaseMacros", type: "EntityRepresentableMacro")

@attached(memberAttribute)
public macro EntityRepresentableRelationship() = #externalMacro(module: "DatabaseMacros", type: "EntityRepresentableRelationshipMacro")

@attached(memberAttribute)
public macro EntityRepresentableIgnorable() = #externalMacro(module: "DatabaseMacros", type: "EntityRepresentableIgnorableMacro")

@attached(memberAttribute)
public macro EntityRepresentableCustomNamed(_ name: String) = #externalMacro(module: "DatabaseMacros", type: "EntityRepresentableCustomNamedMacro")

@attached(memberAttribute)
public macro EntityRepresentableCodable() = #externalMacro(module: "DatabaseMacros", type: "EntityRepresentableCodableMacro")
