# ``Copy_on_Write``

@Metadata {
    @DisplayName("Copy on Write")
    @TitleHeading("Swift Foundations")
}

A macro, `@Copy on Write` (short alias `@CoW`), that transforms a struct's
stored properties into computed properties backed by a private `Storage`
class: mutations call `ensureUnique()` first, copying the storage only when
it is shared, so the struct keeps value semantics at the cost of one
reference on the stack instead of the full property set.

## When to use this

Reach for this macro on structs that are large, frequently copied, but
infrequently mutated — the common case where copy-on-write pays for itself.
It does not make the struct `Sendable` automatically: the generated
`Storage` is `@unchecked Sendable` only when the struct itself explicitly
declares `Sendable` conformance, since the macro cannot verify from syntax
alone that every stored property is safe to share across isolation domains.
Declare `Sendable` only on structs whose properties you have verified are
safe.

## Topics
