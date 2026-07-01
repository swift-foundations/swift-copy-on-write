// CoWMacro.swift
// Implementation of the @CoW macro

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftCompilerPlugin

/// Information about a stored property extracted from the struct
struct StoredProperty {
    let name: String
    let type: TypeSyntax
    let defaultValue: ExprSyntax?
    let accessLevel: String?
    let isVar: Bool
}

// MARK: - CoWMacro

public struct CoWMacro {}

// MARK: - MemberMacro

extension CoWMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Ensure we're attached to a struct
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw CoWMacroError.onlyApplicableToStruct
        }

        // Extract stored properties
        let properties = extractStoredProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw CoWMacroError.noStoredProperties
        }

        // Filter to only var properties for CoW storage
        // let properties stay as regular stored properties on the struct
        let varProperties = properties.filter { $0.isVar }

        guard !varProperties.isEmpty else {
            throw CoWMacroError.noVarProperties
        }

        // Generate the Storage class (only var properties)
        let storageClass = generateStorageClass(properties: varProperties)

        // Generate the storage property
        let storageProperty: DeclSyntax = "private var storage: Storage"

        // Generate ensureUnique method
        // Matches struct's access level so Property _modify accessors can call it.
        let ensureUniqueAccess = extractAccessLevel(from: structDecl.modifiers) ?? "internal"
        let ensureUnique: DeclSyntax = """
            \(raw: ensureUniqueAccess) mutating func ensureUnique() {
                if !isKnownUniquelyReferenced(&storage) {
                    storage = Storage(copying: storage)
                }
            }
            """

        // Generate initializer (only var properties)
        // Use struct's access level for the initializer
        let initializer = generateInitializer(properties: varProperties, structAccessLevel: extractAccessLevel(from: structDecl.modifiers))

        // Generate isIdentical(to:) method
        // Match access level to struct's declared visibility
        let structName = structDecl.name.text
        let structAccessLevel = extractAccessLevel(from: structDecl.modifiers)
        let isIdenticalAccess = structAccessLevel.map { "\($0) " } ?? ""
        let isIdentical: DeclSyntax = """
            /// Returns true if this value and the other value share the same underlying storage.
            /// This can be useful for debugging or testing Copy-on-Write behavior.
            \(raw: isIdenticalAccess)func isIdentical(to other: \(raw: structName)) -> Bool {
                storage === other.storage
            }
            """

        return [
            storageClass,
            storageProperty,
            ensureUnique,
            initializer,
            isIdentical,
        ]
    }
}

// MARK: - ExtensionMacro

extension CoWMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        // Extract stored properties
        let properties = extractStoredProperties(from: structDecl)
        let varProperties = properties.filter { $0.isVar }

        guard !varProperties.isEmpty else {
            return []
        }

        // Check which protocols the struct wants to conform to
        let inheritedTypes = structDecl.inheritanceClause?.inheritedTypes.map {
            $0.type.trimmedDescription
        } ?? []

        var extensions: [ExtensionDeclSyntax] = []

        // Generate Equatable extension if requested
        let wantsEquatable = inheritedTypes.contains("Equatable")
        let wantsHashable = inheritedTypes.contains("Hashable")

        if wantsEquatable || wantsHashable {
            // If struct declares Equatable explicitly, don't re-declare conformance
            // If struct only declares Hashable, we need to add Equatable conformance
            let declareEquatableConformance = !wantsEquatable && wantsHashable
            let equatableExt = try generateEquatableExtension(
                typeName: type,
                properties: varProperties,
                declareConformance: declareEquatableConformance
            )
            extensions.append(equatableExt)
        }

        // Generate Hashable extension if requested
        if wantsHashable {
            let hashableExt = try generateHashableExtension(
                typeName: type,
                properties: varProperties
            )
            extensions.append(hashableExt)
        }

        // Generate Codable extension if requested
        let wantsCodable = inheritedTypes.contains("Codable")
        let wantsEncodable = inheritedTypes.contains("Encodable") || wantsCodable
        let wantsDecodable = inheritedTypes.contains("Decodable") || wantsCodable

        if wantsEncodable || wantsDecodable {
            let codableExt = try generateCodableExtension(
                typeName: type,
                properties: varProperties,
                includeEncodable: wantsEncodable,
                includeDecodable: wantsDecodable
            )
            extensions.append(codableExt)
        }

        // Generate CustomStringConvertible extension if requested
        if inheritedTypes.contains("CustomStringConvertible") {
            let descriptionExt = try generateCustomStringConvertibleExtension(
                typeName: type,
                structName: structDecl.name.text,
                properties: varProperties
            )
            extensions.append(descriptionExt)
        }

        return extensions
    }
}

private func generateEquatableExtension(
    typeName: some TypeSyntaxProtocol,
    properties: [StoredProperty],
    declareConformance: Bool
) throws -> ExtensionDeclSyntax {
    let comparisons = properties.map { prop in
        "lhs.\(prop.name) == rhs.\(prop.name)"
    }.joined(separator: " && ")

    // Only declare conformance if struct doesn't already declare Equatable
    // (e.g., when struct declares Hashable which implies Equatable)
    if declareConformance {
        return try ExtensionDeclSyntax("extension \(typeName): Equatable") {
            """
            public static func == (lhs: \(typeName), rhs: \(typeName)) -> Bool {
                \(raw: comparisons)
            }
            """
        }
    } else {
        return try ExtensionDeclSyntax("extension \(typeName)") {
            """
            public static func == (lhs: \(typeName), rhs: \(typeName)) -> Bool {
                \(raw: comparisons)
            }
            """
        }
    }
}

private func generateHashableExtension(
    typeName: some TypeSyntaxProtocol,
    properties: [StoredProperty]
) throws -> ExtensionDeclSyntax {
    let hashStatements = properties.map { prop in
        "hasher.combine(\(prop.name))"
    }.joined(separator: "\n            ")

    // Don't re-declare conformance - struct already declares it
    return try ExtensionDeclSyntax("extension \(typeName)") {
        """
        public func hash(into hasher: inout Hasher) {
            \(raw: hashStatements)
        }
        """
    }
}

private func generateCodableExtension(
    typeName: some TypeSyntaxProtocol,
    properties: [StoredProperty],
    includeEncodable: Bool,
    includeDecodable: Bool
) throws -> ExtensionDeclSyntax {
    let codingKeys = properties.map { prop in
        "case \(prop.name)"
    }.joined(separator: "\n            ")

    // Don't re-declare conformance - struct already declares it
    return try ExtensionDeclSyntax("extension \(typeName)") {
        """
        private enum CodingKeys: String, CodingKey {
            \(raw: codingKeys)
        }
        """

        if includeEncodable {
            let encodeStatements = properties.map { prop in
                "try container.encode(\(prop.name), forKey: .\(prop.name))"
            }.joined(separator: "\n            ")

            """
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                \(raw: encodeStatements)
            }
            """
        }

        if includeDecodable {
            let decodeStatements = properties.map { prop in
                "let \(prop.name) = try container.decode(\(cleanTypeString(prop.type)).self, forKey: .\(prop.name))"
            }.joined(separator: "\n            ")

            let initArgs = properties.map { prop in
                "\(prop.name): \(prop.name)"
            }.joined(separator: ", ")

            """
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                \(raw: decodeStatements)
                self.init(\(raw: initArgs))
            }
            """
        }
    }
}

private func generateCustomStringConvertibleExtension(
    typeName: some TypeSyntaxProtocol,
    structName: String,
    properties: [StoredProperty]
) throws -> ExtensionDeclSyntax {
    let propertyDescriptions = properties.map { prop in
        "\(prop.name): \\(\(prop.name))"
    }.joined(separator: ", ")

    // Don't re-declare conformance - struct already declares it
    return try ExtensionDeclSyntax("extension \(typeName)") {
        """
        public var description: String {
            "\(raw: structName)(\(raw: propertyDescriptions))"
        }
        """
    }
}

// MARK: - MemberAttributeMacro

extension CoWMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        // Only apply to variable declarations
        guard let varDecl = member.as(VariableDeclSyntax.self) else {
            return []
        }

        // Skip computed properties
        guard !isComputedProperty(varDecl) else {
            return []
        }

        // Skip static properties
        guard !varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
            return []
        }

        // Skip the storage property we generate
        for binding in varDecl.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                if identifier == "storage" {
                    return []
                }
            }
        }

        // Skip let properties - accessor macros can't be attached to let in Swift 6
        // These are handled directly in MemberMacro
        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            return []
        }

        // Add @_CoWProperty to transform this into a computed property
        return [AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("_CoWProperty")))]
    }
}

// MARK: - CoWPropertyMacro (Accessor Macro)

public struct CoWPropertyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
            return []
        }

        let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

        if isLet {
            // Read-only accessor for let properties
            return [
                """
                _read {
                    yield storage.\(raw: identifier)
                }
                """
            ]
        } else {
            // Read-write accessors for var properties
            // _read yields a borrowed reference (avoids copying collections).
            // _modify uses copy-out/yield/write-back to ensure the yielded
            // pointer is always to a stack-local, never into heap storage.
            // This is required for safe composition: when a @CoW property is
            // itself a @CoW type, a nested ensureUnique() could reallocate
            // inner storage while an outer _modify's heap pointer is live,
            // producing a dangling pointer (debug-mode SIGSEGV).
            return [
                """
                _read {
                    yield storage.\(raw: identifier)
                }
                """,
                """
                _modify {
                    ensureUnique()
                    var value = storage.\(raw: identifier)
                    yield &value
                    storage.\(raw: identifier) = value
                }
                """
            ]
        }
    }
}

// MARK: - Helper Functions

private func extractStoredProperties(from structDecl: StructDeclSyntax) -> [StoredProperty] {
    var properties: [StoredProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
            continue
        }

        // Skip computed properties
        guard !isComputedProperty(varDecl) else {
            continue
        }

        // Skip static properties
        guard !varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
            continue
        }

        // Extract access level
        let accessLevel = extractAccessLevel(from: varDecl.modifiers)

        // Check if it's var or let
        let isVar = varDecl.bindingSpecifier.tokenKind == .keyword(.var)

        for binding in varDecl.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                continue
            }

            // Get the type annotation or infer from initializer
            let type: TypeSyntax
            if let typeAnnotation = binding.typeAnnotation?.type {
                type = typeAnnotation
            } else if let initializer = binding.initializer?.value {
                // Try to infer type from literal
                type = inferType(from: initializer) ?? TypeSyntax(IdentifierTypeSyntax(name: .identifier("Any")))
            } else {
                continue // Can't determine type
            }

            let defaultValue = binding.initializer?.value

            properties.append(StoredProperty(
                name: identifier,
                type: type,
                defaultValue: defaultValue,
                accessLevel: accessLevel,
                isVar: isVar
            ))
        }
    }

    return properties
}

private func isComputedProperty(_ varDecl: VariableDeclSyntax) -> Bool {
    for binding in varDecl.bindings {
        if let accessor = binding.accessorBlock {
            switch accessor.accessors {
            case .getter:
                return true
            case .accessors(let accessorList):
                for accessor in accessorList {
                    if accessor.accessorSpecifier.tokenKind == .keyword(.get) ||
                       accessor.accessorSpecifier.tokenKind == .keyword(.set) {
                        return true
                    }
                }
            }
        }
    }
    return false
}

private func extractAccessLevel(from modifiers: DeclModifierListSyntax) -> String? {
    for modifier in modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public): return "public"
        case .keyword(.private): return "private"
        case .keyword(.fileprivate): return "fileprivate"
        case .keyword(.internal): return "internal"
        case .keyword(.package): return "package"
        default: continue
        }
    }
    return nil
}

private func inferType(from expr: ExprSyntax) -> TypeSyntax? {
    if expr.is(IntegerLiteralExprSyntax.self) {
        return TypeSyntax(IdentifierTypeSyntax(name: .identifier("Int")))
    } else if expr.is(FloatLiteralExprSyntax.self) {
        return TypeSyntax(IdentifierTypeSyntax(name: .identifier("Double")))
    } else if expr.is(StringLiteralExprSyntax.self) {
        return TypeSyntax(IdentifierTypeSyntax(name: .identifier("String")))
    } else if expr.is(BooleanLiteralExprSyntax.self) {
        return TypeSyntax(IdentifierTypeSyntax(name: .identifier("Bool")))
    }
    return nil
}

/// Check if a type is optional (ends with ? or is Optional<T>)
private func isOptionalType(_ type: TypeSyntax) -> Bool {
    // Direct optional type: T?
    if type.is(OptionalTypeSyntax.self) {
        return true
    }
    // Implicitly unwrapped optional: T!
    if type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return true
    }
    // Optional<T> syntax
    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == "Optional" {
        return true
    }
    return false
}

// MARK: - Code Generation

/// Safely convert TypeSyntax to a clean string representation.
/// Uses token-based reconstruction to correctly handle all type forms,
/// including value generic parameters (e.g., `Size<1>`) in Swift 6.
private func cleanTypeString(_ type: TypeSyntax) -> String {
    // Collect all tokens and join them with appropriate spacing.
    // This bypasses SwiftSyntax's problematic description for value generics.
    var result = ""
    var previousToken: String = ""

    for token in type.tokens(viewMode: .sourceAccurate) {
        let text = token.text

        // Skip empty tokens
        guard !text.isEmpty else { continue }

        // Determine if we need a space before this token
        if !result.isEmpty && needsSpaceBetween(previousToken, text) {
            result += " "
        }

        result += text
        previousToken = text
    }

    return result
}

/// Determine if a space is needed between two tokens.
private func needsSpaceBetween(_ prev: String, _ next: String) -> Bool {
    // No space after opening brackets/parens
    if prev == "(" || prev == "[" || prev == "<" { return false }

    // No space before closing brackets/parens
    if next == ")" || next == "]" || next == ">" { return false }

    // No space before or after dot
    if prev == "." || next == "." { return false }

    // No space before comma, after comma needs space
    if next == "," { return false }
    if prev == "," { return true }

    // No space before colon in type annotation, space after
    if next == ":" { return false }
    if prev == ":" { return true }

    // No space before or after question mark (optional)
    if next == "?" || prev == "?" { return false }

    // No space before or after exclamation mark (IUO)
    if next == "!" || prev == "!" { return false }

    // No space before or after ampersand in composition types
    if prev == "&" || next == "&" { return true }

    // Space around arrow
    if prev == "->" || next == "->" { return true }

    // Space after keywords
    if prev == "some" || prev == "any" || prev == "inout" ||
       prev == "repeat" || prev == "each" || prev == "throws" ||
       prev == "async" || prev == "rethrows" {
        return true
    }

    // Default: no space (most tokens are joined directly)
    return false
}

/// Safely convert ExprSyntax to a clean string representation.
private func cleanExprString(_ expr: ExprSyntax) -> String {
    var result = expr.trimmedDescription
    // Collapse multiple whitespace to single space
    while result.contains("  ") {
        result = result.replacing("  ", with: " ")
    }
    return result
}

private func generateStorageClass(properties: [StoredProperty]) -> DeclSyntax {
    // Generate storage properties
    let storageProperties = properties.map { prop -> String in
        "var \(prop.name): \(cleanTypeString(prop.type))"
    }.joined(separator: "\n        ")

    // Generate primary initializer parameters
    // Optional types without explicit defaults get `= nil`
    let initParams = properties.map { prop -> String in
        let typeStr = cleanTypeString(prop.type)
        if let defaultValue = prop.defaultValue {
            return "\(prop.name): \(typeStr) = \(cleanExprString(defaultValue))"
        } else if isOptionalType(prop.type) {
            return "\(prop.name): \(typeStr) = nil"
        } else {
            return "\(prop.name): \(typeStr)"
        }
    }.joined(separator: ", ")

    // Generate primary initializer assignments
    let initAssignments = properties.map { prop -> String in
        "self.\(prop.name) = \(prop.name)"
    }.joined(separator: "\n            ")

    // Generate copying initializer assignments
    let copyAssignments = properties.map { prop -> String in
        "self.\(prop.name) = other.\(prop.name)"
    }.joined(separator: "\n            ")

    return """
        // MARK: - CoW Generated Storage
        private final class Storage: @unchecked Sendable {
            \(raw: storageProperties)

            init(\(raw: initParams)) {
                \(raw: initAssignments)
            }

            init(copying other: Storage) {
                \(raw: copyAssignments)
            }
        }
        """
}

private func generateInitializer(properties: [StoredProperty], structAccessLevel: String?) -> DeclSyntax {
    // Use struct's access level for the initializer
    let accessModifier = structAccessLevel.map { "\($0) " } ?? ""

    // Generate initializer parameters
    // Optional types without explicit defaults get `= nil`
    let initParams = properties.map { prop -> String in
        let typeStr = cleanTypeString(prop.type)
        if let defaultValue = prop.defaultValue {
            return "\(prop.name): \(typeStr) = \(cleanExprString(defaultValue))"
        } else if isOptionalType(prop.type) {
            return "\(prop.name): \(typeStr) = nil"
        } else {
            return "\(prop.name): \(typeStr)"
        }
    }.joined(separator: ", ")

    // Generate storage initialization arguments
    let storageArgs = properties.map { prop -> String in
        "\(prop.name): \(prop.name)"
    }.joined(separator: ", ")

    return """
        \(raw: accessModifier)init(\(raw: initParams)) {
            self.storage = Storage(\(raw: storageArgs))
        }
        """
}

// MARK: - Errors

enum CoWMacroError: Error, CustomStringConvertible {
    case onlyApplicableToStruct
    case noStoredProperties
    case noVarProperties

    var description: String {
        switch self {
        case .onlyApplicableToStruct:
            return "@CoW can only be applied to structs. Classes, enums, and actors are not supported."
        case .noStoredProperties:
            return "@CoW requires at least one stored property. Add a 'var' property to your struct."
        case .noVarProperties:
            return "@CoW requires at least one 'var' property. Change 'let' to 'var' or use 'private(set) var' for read-only properties."
        }
    }
}
