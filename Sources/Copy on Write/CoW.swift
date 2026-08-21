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

@attached(accessor, names: named(_read), named(_modify))
public macro _CoWProperty() =
    #externalMacro(module: "Copy_on_Write_Macros", type: "CoWPropertyMacro")
