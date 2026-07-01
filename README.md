# swift-copy-on-write

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Transforms a struct into a copy-on-write type with a single macro, so its stored properties live in shared reference-counted storage that is copied only when a shared instance is mutated.

---

## Key Features

- **One macro, no boilerplate** — `@CoW` rewrites a struct's stored `var` properties into accessors over a generated reference-counted `Storage` class, replacing the hand-written copy-on-write pattern.
- **Copy only on mutation** — copies share a single `Storage`; the backing buffer is duplicated lazily through `isKnownUniquelyReferenced`, and only when a shared instance is first mutated.
- **Value semantics intact** — mutating one copy never affects another, exactly as with a plain struct.
- **Single-reference footprint** — the wrapped value is one reference, so large payloads are passed and copied as a pointer until a write forces a real copy.
- **Synthesized conformances** — declaring `Equatable`, `Hashable`, `Codable`, or `CustomStringConvertible` on the struct generates the matching witnesses over its stored properties.
- **Storage-identity check** — a generated `isIdentical(to:)` reports whether two values still share the same `Storage`, which makes copy-on-write behavior directly testable.
- **Composable mutation** — `var` properties expose `_read` / `_modify` accessors, so in-place mutation and nested `@CoW` types compose without dangling-pointer hazards.

---

## Quick Start

Applying `@CoW` replaces the manual copy-on-write pattern — a private `Storage` class, an `isKnownUniquelyReferenced` guard, and a copying accessor for every property — with one attribute:

```swift
import Copy_on_Write

// Copied often, mutated rarely.
@CoW
struct Document: Equatable {
    var title: String
    var paragraphs: [String]
    var wordCount: Int = 0
}

let chapter = Document(title: "Chapter 1", paragraphs: Array(repeating: "lorem ipsum", count: 100_000))

var working = chapter                      // No payload copy — both share one Storage.
print(working.isIdentical(to: chapter))    // true

working.wordCount = 200                     // First mutation copies the payload once, for `working` only.
print(working.isIdentical(to: chapter))    // false
print(chapter.wordCount)                    // 0 — `chapter` is untouched.
```

`@CoW` is shorthand; the full-name spelling is identical, and declaring a conformance synthesizes its witnesses over the stored properties:

```swift
@`Copy on Write`
struct Settings: Hashable {
    var theme: String
    var fontSize: Int
}
```

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-copy-on-write.git", branch: "main")
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Copy on Write", package: "swift-copy-on-write")
    ]
)
```

Requires Swift 6.3.1 and the macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 platform minimums declared in the manifest.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public flip.*
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE](LICENSE.md).
