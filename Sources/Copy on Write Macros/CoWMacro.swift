import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct StoredProperty {
    let name: String
    let type: TypeSyntax
    let defaultValue: ExprSyntax?
    let accessLevel: String?
    let isVar: Bool
}

public struct CoWMacro {}

extension CoWMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw CoWMacroError.onlyApplicableToStruct
        }

        let properties = extractStoredProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw CoWMacroError.noStoredProperties
        }

        let varProperties = properties.filter { $0.isVar }

        guard !varProperties.isEmpty else {
            throw CoWMacroError.noVarProperties
        }

        let inheritedTypeNames =
            structDecl.inheritanceClause?.inheritedTypes.map {
                $0.type.trimmedDescription
            } ?? []
        let wantsSendable = inheritedTypeNames.contains("Sendable")

        if wantsSendable {
            for property in varProperties where containsFunctionType(property.type) {
                context.diagnose(
                    Diagnostic(
                        node: property.type,
                        message: CoWMacroDiagnostic.uncheckedSendableFunctionProperty(
                            propertyName: property.name
                        )
                    )
                )
            }
        }

        let storageClass = generateStorageClass(
            properties: varProperties,
            isSendable: wantsSendable
        )

        let storageProperty: DeclSyntax = "private var storage: Storage"

        let ensureUniqueAccess = extractAccessLevel(from: structDecl.modifiers) ?? "internal"
        let ensureUnique: DeclSyntax = """
            \(raw: ensureUniqueAccess) mutating func ensureUnique() {
                if !isKnownUniquelyReferenced(&storage) {
                    storage = Storage(copying: storage)
                }
            }
            """

        let initializer = generateInitializer(
            properties: varProperties,
            structAccessLevel: extractAccessLevel(from: structDecl.modifiers)
        )

        let structName = structDecl.name.text
        let structAccessLevel = extractAccessLevel(from: structDecl.modifiers)
        let isIdenticalAccess = structAccessLevel.map { "\($0) " } ?? ""
        let isIdentical: DeclSyntax = """
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

        let properties = extractStoredProperties(from: structDecl)
        let varProperties = properties.filter { $0.isVar }

        guard !varProperties.isEmpty else {
            return []
        }

        let inheritedTypes =
            structDecl.inheritanceClause?.inheritedTypes.map {
                $0.type.trimmedDescription
            } ?? []

        var extensions: [ExtensionDeclSyntax] = []

        let wantsEquatable = inheritedTypes.contains("Equatable")
        let wantsHashable = inheritedTypes.contains("Hashable")

        if wantsEquatable || wantsHashable {

            let declareEquatableConformance = !wantsEquatable && wantsHashable
            let equatableExt = try generateEquatableExtension(
                typeName: type,
                properties: varProperties,
                declareConformance: declareEquatableConformance
            )
            extensions.append(equatableExt)
        }

        if wantsHashable {
            let hashableExt = try generateHashableExtension(
                typeName: type,
                properties: varProperties
            )
            extensions.append(hashableExt)
        }

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
) throws(CoWMacroError) -> ExtensionDeclSyntax {
    let comparisons = properties.map { prop in
        "lhs.\(prop.name) == rhs.\(prop.name)"
    }.joined(separator: " && ")

    do {

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
    } catch {
        throw CoWMacroError.syntaxGenerationFailed(String(describing: error))
    }
}

private func generateHashableExtension(
    typeName: some TypeSyntaxProtocol,
    properties: [StoredProperty]
) throws(CoWMacroError) -> ExtensionDeclSyntax {
    let hashStatements = properties.map { prop in
        "hasher.combine(\(prop.name))"
    }.joined(separator: "\n            ")

    do {

        return try ExtensionDeclSyntax("extension \(typeName)") {
            """
            public func hash(into hasher: inout Hasher) {
                \(raw: hashStatements)
            }
            """
        }
    } catch {
        throw CoWMacroError.syntaxGenerationFailed(String(describing: error))
    }
}

private func generateCodableExtension(
    typeName: some TypeSyntaxProtocol,
    properties: [StoredProperty],
    includeEncodable: Bool,
    includeDecodable: Bool
) throws(CoWMacroError) -> ExtensionDeclSyntax {
    let codingKeys = properties.map { prop in
        "case \(prop.name)"
    }.joined(separator: "\n            ")

    do {

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
    } catch {
        throw CoWMacroError.syntaxGenerationFailed(String(describing: error))
    }
}

private func generateCustomStringConvertibleExtension(
    typeName: some TypeSyntaxProtocol,
    structName: String,
    properties: [StoredProperty]
) throws(CoWMacroError) -> ExtensionDeclSyntax {
    let propertyDescriptions = properties.map { prop in
        "\(prop.name): \\(\(prop.name))"
    }.joined(separator: ", ")

    do {

        return try ExtensionDeclSyntax("extension \(typeName)") {
            """
            public var description: String {
                "\(raw: structName)(\(raw: propertyDescriptions))"
            }
            """
        }
    } catch {
        throw CoWMacroError.syntaxGenerationFailed(String(describing: error))
    }
}

extension CoWMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {

        guard let varDecl = member.as(VariableDeclSyntax.self) else {
            return []
        }

        guard !isComputedProperty(varDecl) else {
            return []
        }

        guard !varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
            return []
        }

        for binding in varDecl.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                if identifier == "storage" {
                    return []
                }
            }
        }

        guard varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
            return []
        }

        return [
            AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("_CoWProperty")))
        ]
    }
}

public struct CoWPropertyMacro {}

extension CoWPropertyMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
            let binding = varDecl.bindings.first,
            let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        else {
            return []
        }

        let isLet = varDecl.bindingSpecifier.tokenKind == .keyword(.let)

        if isLet {

            return [
                """
                _read {
                    yield storage.\(raw: identifier)
                }
                """
            ]
        } else {

            return [
                """
                _read {
                    yield storage.\(raw: identifier)
                }
                """,
                """
                _modify {
                    ensureUnique()
                    yield &storage.\(raw: identifier)
                }
                """,
            ]
        }
    }
}

private func extractStoredProperties(from structDecl: StructDeclSyntax) -> [StoredProperty] {
    var properties: [StoredProperty] = []

    for member in structDecl.memberBlock.members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
            continue
        }

        guard !isComputedProperty(varDecl) else {
            continue
        }

        guard !varDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) else {
            continue
        }

        let accessLevel = extractAccessLevel(from: varDecl.modifiers)

        let isVar = varDecl.bindingSpecifier.tokenKind == .keyword(.var)

        for binding in varDecl.bindings {
            guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            else {
                continue
            }

            let type: TypeSyntax
            if let typeAnnotation = binding.typeAnnotation?.type {
                type = typeAnnotation
            } else if let initializer = binding.initializer?.value {

                type =
                    inferType(from: initializer)
                    ?? TypeSyntax(IdentifierTypeSyntax(name: .identifier("Any")))
            } else {
                continue
            }

            let defaultValue = binding.initializer?.value

            properties.append(
                StoredProperty(
                    name: identifier,
                    type: type,
                    defaultValue: defaultValue,
                    accessLevel: accessLevel,
                    isVar: isVar
                )
            )
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
                    if accessor.accessorSpecifier.tokenKind == .keyword(.get)
                        || accessor.accessorSpecifier.tokenKind == .keyword(.set)
                    {
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

private func isOptionalType(_ type: TypeSyntax) -> Bool {

    if type.is(OptionalTypeSyntax.self) {
        return true
    }

    if type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return true
    }

    if let identifier = type.as(IdentifierTypeSyntax.self),
        identifier.name.text == "Optional"
    {
        return true
    }
    return false
}

private func containsFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) {
        return true
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return containsFunctionType(optional.wrappedType)
    }
    if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return containsFunctionType(iuo.wrappedType)
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return containsFunctionType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1 {
        return containsFunctionType(tuple.elements[tuple.elements.startIndex].type)
    }
    return false
}

private func cleanTypeString(_ type: TypeSyntax) -> String {

    var result = ""
    var previousToken: String = ""

    for token in type.tokens(viewMode: .sourceAccurate) {
        let text = token.text

        guard !text.isEmpty else { continue }

        if !result.isEmpty && needsSpaceBetween(previousToken, text) {
            result += " "
        }

        result += text
        previousToken = text
    }

    return result
}

private func needsSpaceBetween(_ prev: String, _ next: String) -> Bool {

    if prev == "(" || prev == "[" || prev == "<" { return false }

    if next == ")" || next == "]" || next == ">" { return false }

    if prev == "." || next == "." { return false }

    if next == "," { return false }
    if prev == "," { return true }

    if next == ":" { return false }
    if prev == ":" { return true }

    if next == "?" || prev == "?" { return false }

    if next == "!" || prev == "!" { return false }

    if prev == "&" || next == "&" { return true }

    if prev == "->" || next == "->" { return true }

    if prev == "some" || prev == "any" || prev == "inout" || prev == "repeat" || prev == "each"
        || prev == "throws" || prev == "async" || prev == "rethrows"
    {
        return true
    }

    return false
}

private func cleanExprString(_ expr: ExprSyntax) -> String {
    var result = expr.trimmedDescription

    while result.contains("  ") {
        result = result.replacing("  ", with: " ")
    }
    return result
}

private func generateStorageClass(properties: [StoredProperty], isSendable: Bool) -> DeclSyntax {

    let storageProperties = properties.map { prop -> String in
        "var \(prop.name): \(cleanTypeString(prop.type))"
    }.joined(separator: "\n        ")

    let sendableConformance = isSendable ? ": @unchecked Sendable" : ""

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

    let initAssignments = properties.map { prop -> String in
        "self.\(prop.name) = \(prop.name)"
    }.joined(separator: "\n            ")

    let copyAssignments = properties.map { prop -> String in
        "self.\(prop.name) = other.\(prop.name)"
    }.joined(separator: "\n            ")

    return """
        // MARK: - CoW Generated Storage
        private final class Storage\(raw: sendableConformance) {
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

private func generateInitializer(
    properties: [StoredProperty],
    structAccessLevel: String?
) -> DeclSyntax {

    let accessModifier = structAccessLevel.map { "\($0) " } ?? ""

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

    let storageArgs = properties.map { prop -> String in
        "\(prop.name): \(prop.name)"
    }.joined(separator: ", ")

    return """
        \(raw: accessModifier)init(\(raw: initParams)) {
            self.storage = Storage(\(raw: storageArgs))
        }
        """
}

enum CoWMacroError: Swift.Error, CustomStringConvertible {
    case onlyApplicableToStruct
    case noStoredProperties
    case noVarProperties
    case syntaxGenerationFailed(String)
}

extension CoWMacroError {
    var description: String {
        switch self {
        case .onlyApplicableToStruct:
            return
                "@CoW can only be applied to structs. Classes, enums, and actors are not supported."

        case .noStoredProperties:
            return
                "@CoW requires at least one stored property. Add a 'var' property to your struct."

        case .noVarProperties:
            return
                "@CoW requires at least one 'var' property. Change 'let' to 'var' or use 'private(set) var' for read-only properties."

        case .syntaxGenerationFailed(let detail):
            return
                "@CoW failed to build generated syntax internally (\(detail)). This indicates a bug in the macro implementation."
        }
    }
}

struct CoWMacroDiagnostic: DiagnosticMessage {
    private let propertyName: String

    static func uncheckedSendableFunctionProperty(propertyName: String) -> CoWMacroDiagnostic {
        CoWMacroDiagnostic(propertyName: propertyName)
    }

    var message: String {
        "Generated Storage is '@unchecked Sendable' because this struct declares 'Sendable', "
            + "but property '\(propertyName)' has a function type. Closures are not verified "
            + "Sendable-safe by the compiler — confirm captured state is safe to share across "
            + "isolation domains, or remove the 'Sendable' conformance."
    }

    var diagnosticID: MessageID {
        MessageID(domain: "CoWMacro", id: "uncheckedSendableFunctionProperty")
    }

    var severity: DiagnosticSeverity { .warning }
}
