// CoW.swift
// Copy-on-Write macro for Swift structs

/// Transforms a struct into a Copy-on-Write (CoW) type.
///
/// CoW provides value semantics with efficient copying - the underlying storage
/// is only copied when a mutation occurs on a shared instance. This is ideal for
/// large structs that are frequently passed around but infrequently mutated.
///
/// ## Usage
///
/// ```swift
/// @`Copy on Write`
/// public struct Context {
///     public var layoutBox: Rectangle
///     public var style: Style
///     internal var counter: Int = 0
/// }
/// ```
///
/// You can also use the shorter alias `@CoW`:
///
/// ```swift
/// @CoW
/// public struct Context {
///     public var layoutBox: Rectangle
///     public var style: Style
///     internal var counter: Int = 0
/// }
/// ```
///
/// ## Expansion
///
/// The macro transforms stored properties into computed properties backed by a
/// private `Storage` class:
///
/// ```swift
/// public struct Context {
///     private final class Storage: @unchecked Sendable {
///         var layoutBox: Rectangle
///         var style: Style
///         var counter: Int
///
///         init(layoutBox: Rectangle, style: Style, counter: Int = 0) { ... }
///         init(copying other: Storage) { ... }
///     }
///
///     private var storage: Storage
///
///     public mutating func ensureUnique() {
///         if !isKnownUniquelyReferenced(&storage) {
///             storage = Storage(copying: storage)
///         }
///     }
///
///     public var layoutBox: Rectangle {
///         _read { yield storage.layoutBox }
///         _modify { ensureUnique(); yield &storage.layoutBox }
///     }
///     // ... etc
/// }
/// ```
///
/// ## Benefits
///
/// - **Stack efficiency**: Only 8 bytes on stack (single reference)
/// - **Value semantics**: Mutations don't affect other copies
/// - **Lazy copying**: Storage only copied when needed
/// - **Sendable by default**: Generated Storage is `@unchecked Sendable`
///
@attached(
    member,
    names: named(Storage),
    named(storage),
    named(ensureUnique),
    named(init),
    named(isIdentical)
)
@attached(memberAttribute)
@attached(
    extension,
    conformances: Equatable,
    Hashable,
    Decodable,
    Encodable,
    CustomStringConvertible,
    names: named(==),
    named(hash),
    named(encode),
    named(init),
    named(CodingKeys),
    named(description)
)
public macro `Copy on Write`() = #externalMacro(module: "Copy_on_Write_Macros", type: "CoWMacro")

/// Short alias for `@Copy on Write` macro.
@attached(
    member,
    names: named(Storage),
    named(storage),
    named(ensureUnique),
    named(init),
    named(isIdentical)
)
@attached(memberAttribute)
@attached(
    extension,
    conformances: Equatable,
    Hashable,
    Decodable,
    Encodable,
    CustomStringConvertible,
    names: named(==),
    named(hash),
    named(encode),
    named(init),
    named(CodingKeys),
    named(description)
)
public macro CoW() = #externalMacro(module: "Copy_on_Write_Macros", type: "CoWMacro")

/// Internal macro applied to properties by @`Copy on Write` to provide accessor implementations.
/// This transforms stored properties into computed properties that delegate to Storage.
///
/// Generates `_read/_modify` accessors for `var` properties (enabling in-place mutation
/// and composable `_modify` chains), and `_read` for `let` properties.
@attached(accessor, names: named(_read), named(_modify))
public macro _CoWProperty() =
    #externalMacro(module: "Copy_on_Write_Macros", type: "CoWPropertyMacro")
