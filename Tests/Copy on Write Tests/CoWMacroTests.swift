import Copy_on_Write
import Copy_on_Write_Macros
import Foundation
import Testing

@CoW
struct Point {
    var x: Int
    var y: Int
}

@CoW
struct Counter {
    var count: Int = 0
    var name: String
}

@CoW
struct MixedAccess {
    public var publicValue: Int
    internal var internalValue: String
}

@CoW
struct WithPrivateSet {
    private(set) var id: String
    var value: Int
}

@`Copy on Write`
struct FullNamedMacro {
    var name: String
    var count: Int = 0
}

@CoW
struct EquatablePoint: Equatable {
    var x: Int
    var y: Int
}

@CoW
struct HashablePoint: Hashable {
    var x: Int
    var y: Int
}

@CoW
struct CodablePerson: Codable {
    var name: String
    var age: Int
}

@CoW
struct DescribablePoint: CustomStringConvertible {
    var x: Int
    var y: Int
}

@CoW
struct WithOptional {
    var name: String
    var nickname: String?
    var age: Int = 0
}

@CoW
struct Inner {
    var value: Int
}

@CoW
struct Outer {
    var inner: Inner
    var label: String
}

@CoW
struct WithComputed {
    var width: Int
    var height: Int

    var area: Int {
        width * height
    }
}

@CoW
struct WithLabeledTupleArray {
    var items: [(name: String, value: Int)]
}

@CoW
struct WithOptionalTuple {
    var pair: (first: String, second: Int)?
}

@CoW
struct WithNestedGeneric {
    var data: [String: [Int]]
}

@CoW
struct WithFunctionType {
    var handler: ((Int) -> Void)?
}

@CoW
struct WithDictionary {
    var mapping: [String: Int]
}

struct ValueGeneric<let N: Int> {
    var value: Int
}

@CoW
struct WithValueGeneric {
    var size: ValueGeneric<1>
    var optionalSize: ValueGeneric<2>?
}

@CoW
struct DeepInner {
    var value: Int
}

@CoW
struct DeepMiddle {
    var inner: DeepInner
    var label: String
}

@CoW
struct DeepOuter {
    var middle: DeepMiddle
    var tag: Int
}

@CoW
struct InnerWithArray {
    var items: [Int]
}

@CoW
struct OuterWithArray {
    var nested: InnerWithArray
    var name: String
}

@CoW
struct SendableGatingOptedOut {
    var value: Int
}

@CoW
struct SendableGatingOptedIn: Sendable {
    var value: Int
}

@Suite("Copy on Write Macro Tests")
struct CopyOnWriteTests {

    @Test
    func `Basic CoW value semantics`() {
        var p1 = Point(x: 10, y: 20)
        let p2 = p1

        #expect(p1.x == p2.x)
        #expect(p1.y == p2.y)

        p1.x = 100

        #expect(p1.x == 100)
        #expect(p2.x == 10)
    }

    @Test
    func `Default values are preserved`() {
        let c1 = Counter(name: "Test")
        #expect(c1.count == 0)
        #expect(c1.name == "Test")

        let c2 = Counter(count: 5, name: "Custom")
        #expect(c2.count == 5)
    }

    @Test
    func `CoW semantics - copy on mutation`() {
        var c1 = Counter(count: 1, name: "Original")
        let c2 = c1

        c1.count = 999
        c1.name = "Modified"

        #expect(c2.count == 1)
        #expect(c2.name == "Original")

        #expect(c1.count == 999)
        #expect(c1.name == "Modified")
    }

    @Test
    func `private(set) properties work with CoW`() {
        let w = WithPrivateSet(id: "abc", value: 42)
        #expect(w.id == "abc")
        #expect(w.value == 42)

        var w2 = w
        w2.value = 100
        #expect(w2.value == 100)
        #expect(w2.id == "abc")
    }

    @Test
    func `Mixed access levels`() {
        var m = MixedAccess(publicValue: 1, internalValue: "test")
        #expect(m.publicValue == 1)
        #expect(m.internalValue == "test")

        m.publicValue = 2
        m.internalValue = "modified"
        #expect(m.publicValue == 2)
        #expect(m.internalValue == "modified")
    }

    @Test
    func `Multiple copies maintain independence`() {
        var original = Point(x: 1, y: 1)
        var copy1 = original
        var copy2 = original
        var copy3 = copy1

        #expect(original.x == 1)
        #expect(copy1.x == 1)
        #expect(copy2.x == 1)
        #expect(copy3.x == 1)

        original.x = 10
        copy1.x = 20
        copy2.x = 30
        copy3.x = 40

        #expect(original.x == 10)
        #expect(copy1.x == 20)
        #expect(copy2.x == 30)
        #expect(copy3.x == 40)
    }

    @Test
    func `No unnecessary copy on unique reference`() {
        var p = Point(x: 1, y: 2)

        let _ = p.x
        let _ = p.y

        p.x = 10
        #expect(p.x == 10)
    }

    @Test("@`Copy on Write` full name works same as @CoW")
    func fullNamedMacro() {
        var f1 = FullNamedMacro(name: "Test")
        let f2 = f1

        #expect(f1.name == "Test")
        #expect(f1.count == 0)
        #expect(f2.name == "Test")

        f1.name = "Modified"
        f1.count = 5

        #expect(f1.name == "Modified")
        #expect(f1.count == 5)
        #expect(f2.name == "Test")
        #expect(f2.count == 0)
    }

    @Test
    func `isIdentical returns true for shared storage`() {
        let p1 = Point(x: 10, y: 20)
        let p2 = p1

        #expect(p1.isIdentical(to: p2))
    }

    @Test
    func `isIdentical returns false after mutation`() {
        var p1 = Point(x: 10, y: 20)
        let p2 = p1

        p1.x = 100

        #expect(!p1.isIdentical(to: p2))
    }

    @Test
    func `Equatable conformance works`() {
        let p1 = EquatablePoint(x: 10, y: 20)
        let p2 = EquatablePoint(x: 10, y: 20)
        let p3 = EquatablePoint(x: 10, y: 30)

        #expect(p1 == p2)
        #expect(p1 != p3)
    }

    @Test
    func `Equatable works with copies`() {
        var p1 = EquatablePoint(x: 10, y: 20)
        let p2 = p1

        #expect(p1 == p2)

        p1.x = 100

        #expect(p1 != p2)
    }

    @Test
    func `Hashable conformance works`() {
        let p1 = HashablePoint(x: 10, y: 20)
        let p2 = HashablePoint(x: 10, y: 20)
        let p3 = HashablePoint(x: 10, y: 30)

        #expect(p1.hashValue == p2.hashValue)
        #expect(p1.hashValue != p3.hashValue)
    }

    @Test
    func `Hashable works in Set`() {
        let p1 = HashablePoint(x: 10, y: 20)
        let p2 = HashablePoint(x: 10, y: 20)
        let p3 = HashablePoint(x: 30, y: 40)

        var set: Set<HashablePoint> = [p1, p2, p3]
        #expect(set.count == 2)

        set.insert(HashablePoint(x: 50, y: 60))
        #expect(set.count == 3)
    }

    @Test
    func `Encodable conformance works`() throws {
        let person = CodablePerson(name: "Alice", age: 30)
        let encoder = JSONEncoder()
        let data = try encoder.encode(person)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("\"name\":\"Alice\"") || json.contains("\"name\": \"Alice\""))
        #expect(json.contains("\"age\":30") || json.contains("\"age\": 30"))
    }

    @Test
    func `Decodable conformance works`() throws {
        let json = #"{"name":"Bob","age":25}"#
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let person = try decoder.decode(CodablePerson.self, from: data)

        #expect(person.name == "Bob")
        #expect(person.age == 25)
    }

    @Test
    func `Codable round-trip works`() throws {
        let original = CodablePerson(name: "Charlie", age: 35)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CodablePerson.self, from: data)

        #expect(decoded.name == original.name)
        #expect(decoded.age == original.age)
    }

    @Test
    func `CustomStringConvertible conformance works`() {
        let p = DescribablePoint(x: 10, y: 20)
        let description = p.description

        #expect(description.contains("DescribablePoint"))
        #expect(description.contains("x: 10"))
        #expect(description.contains("y: 20"))
    }

    @Test
    func `CustomStringConvertible works with String interpolation`() {
        let p = DescribablePoint(x: 5, y: 15)
        let str = "\(p)"

        #expect(str == "DescribablePoint(x: 5, y: 15)")
    }

    @Test
    func `Optional properties work with CoW`() {
        var w1 = WithOptional(name: "Test", nickname: nil)
        #expect(w1.name == "Test")
        #expect(w1.nickname == nil)
        #expect(w1.age == 0)

        w1.nickname = "Testy"
        #expect(w1.nickname == "Testy")

        let w2 = WithOptional(name: "Full", nickname: "Nick", age: 25)
        #expect(w2.nickname == "Nick")
        #expect(w2.age == 25)
    }

    @Test
    func `Optional properties maintain value semantics`() {
        var w1 = WithOptional(name: "Original", nickname: "Nick")
        let w2 = w1

        w1.nickname = "Changed"

        #expect(w1.nickname == "Changed")
        #expect(w2.nickname == "Nick")
    }

    @Test
    func `Nested CoW structs work`() {
        let inner = Inner(value: 42)
        var outer = Outer(inner: inner, label: "Test")

        #expect(outer.inner.value == 42)
        #expect(outer.label == "Test")

        outer.inner = Inner(value: 100)
        #expect(outer.inner.value == 100)
    }

    @Test
    func `Nested CoW structs maintain value semantics`() {
        let inner = Inner(value: 42)
        var outer1 = Outer(inner: inner, label: "Original")
        let outer2 = outer1

        outer1.inner = Inner(value: 999)

        #expect(outer1.inner.value == 999)
        #expect(outer2.inner.value == 42)
    }

    @Test
    func `Computed properties are preserved`() {
        let rect = WithComputed(width: 10, height: 5)
        #expect(rect.area == 50)
    }

    @Test
    func `Computed properties work with mutations`() {
        var rect = WithComputed(width: 10, height: 5)
        #expect(rect.area == 50)

        rect.width = 20
        #expect(rect.area == 100)
    }

    @Test
    func `Labeled tuple array works`() {
        var s = WithLabeledTupleArray(items: [(name: "a", value: 1), (name: "b", value: 2)])
        #expect(s.items.count == 2)
        #expect(s.items[0].name == "a")
        #expect(s.items[0].value == 1)

        s.items.append((name: "c", value: 3))
        #expect(s.items.count == 3)
    }

    @Test
    func `Labeled tuple array maintains value semantics`() {
        var s1 = WithLabeledTupleArray(items: [(name: "a", value: 1)])
        let s2 = s1

        s1.items.append((name: "b", value: 2))

        #expect(s1.items.count == 2)
        #expect(s2.items.count == 1)
    }

    @Test
    func `Optional labeled tuple works`() {
        var s = WithOptionalTuple(pair: (first: "hello", second: 42))
        #expect(s.pair?.first == "hello")
        #expect(s.pair?.second == 42)

        s.pair = nil
        #expect(s.pair == nil)

        s.pair = (first: "world", second: 100)
        #expect(s.pair?.first == "world")
    }

    @Test
    func `Nested generic dictionary works`() {
        var s = WithNestedGeneric(data: ["a": [1, 2, 3], "b": [4, 5]])
        #expect(s.data["a"]?.count == 3)
        #expect(s.data["b"]?.count == 2)

        s.data["c"] = [6, 7, 8, 9]
        #expect(s.data["c"]?.count == 4)
    }

    @Test
    func `Function type works`() {
        var callCount = 0
        var s = WithFunctionType(handler: { _ in callCount += 1 })

        s.handler?(42)
        #expect(callCount == 1)

        s.handler = nil
        s.handler?(42)
        #expect(callCount == 1)
    }

    @Test
    func `Dictionary type works`() {
        var s = WithDictionary(mapping: ["a": 1, "b": 2])
        #expect(s.mapping["a"] == 1)
        #expect(s.mapping["b"] == 2)

        s.mapping["c"] = 3
        #expect(s.mapping["c"] == 3)
    }

    @Test
    func `Dictionary type maintains value semantics`() {
        var s1 = WithDictionary(mapping: ["a": 1])
        let s2 = s1

        s1.mapping["b"] = 2

        #expect(s1.mapping.count == 2)
        #expect(s2.mapping.count == 1)
    }

    @Test
    func `Value generic parameters work`() {
        let s = WithValueGeneric(
            size: ValueGeneric(value: 42),
            optionalSize: ValueGeneric(value: 100)
        )
        #expect(s.size.value == 42)
        #expect(s.optionalSize?.value == 100)
    }

    @Test
    func `Value generic parameters maintain value semantics`() {
        var s1 = WithValueGeneric(size: ValueGeneric(value: 42), optionalSize: nil)
        let s2 = s1

        s1.size = ValueGeneric(value: 999)

        #expect(s1.size.value == 999)
        #expect(s2.size.value == 42)
    }

    @Test
    func `Nested in-place mutation through _modify chain`() {
        var outer = Outer(inner: Inner(value: 42), label: "test")

        outer.inner.value = 100

        #expect(outer.inner.value == 100)
        #expect(outer.label == "test")
    }

    @Test
    func `Nested in-place mutation with shared outer storage`() {
        var outer1 = Outer(inner: Inner(value: 42), label: "original")
        let outer2 = outer1

        #expect(outer1.isIdentical(to: outer2))

        outer1.inner.value = 999

        #expect(outer1.inner.value == 999)
        #expect(outer2.inner.value == 42)
        #expect(outer1.label == "original")
        #expect(outer2.label == "original")
        #expect(!outer1.isIdentical(to: outer2))
    }

    @Test
    func `Triple-nested in-place mutation`() {
        var deep1 = DeepOuter(
            middle: DeepMiddle(inner: DeepInner(value: 1), label: "mid"),
            tag: 0
        )
        let deep2 = deep1

        deep1.middle.inner.value = 42

        #expect(deep1.middle.inner.value == 42)
        #expect(deep2.middle.inner.value == 1)
        #expect(deep1.middle.label == "mid")
        #expect(deep1.tag == 0)
    }

    @Test
    func `Triple-nested label mutation preserves sibling values`() {
        var deep1 = DeepOuter(
            middle: DeepMiddle(inner: DeepInner(value: 7), label: "before"),
            tag: 99
        )
        let deep2 = deep1

        deep1.middle.label = "after"

        #expect(deep1.middle.label == "after")
        #expect(deep1.middle.inner.value == 7)
        #expect(deep2.middle.label == "before")
        #expect(deep2.middle.inner.value == 7)
    }

    @Test
    func `Repeated nested mutations maintain correctness`() {
        var outer = Outer(inner: Inner(value: 0), label: "counter")

        (1...100).forEach { i in
            outer.inner.value = i
        }

        #expect(outer.inner.value == 100)
        #expect(outer.label == "counter")
    }

    @Test
    func `Nested mutation after multiple copies`() {
        var original = Outer(inner: Inner(value: 1), label: "root")
        let copy1 = original
        let copy2 = original
        let copy3 = copy1

        #expect(original.isIdentical(to: copy1))
        #expect(original.isIdentical(to: copy2))
        #expect(copy1.isIdentical(to: copy3))

        original.inner.value = 999

        #expect(original.inner.value == 999)
        #expect(!original.isIdentical(to: copy1))
        #expect(copy1.inner.value == 1)
        #expect(copy2.inner.value == 1)
        #expect(copy3.inner.value == 1)
    }

    @Test
    func `Collection mutation through nested CoW`() {
        var s1 = OuterWithArray(
            nested: InnerWithArray(items: [1, 2, 3]),
            name: "test"
        )
        let s2 = s1

        s1.nested.items.append(4)

        #expect(s1.nested.items == [1, 2, 3, 4])
        #expect(s2.nested.items == [1, 2, 3])
    }

    @Test
    func `In-place subscript mutation through nested CoW`() {
        var s1 = OuterWithArray(
            nested: InnerWithArray(items: [10, 20, 30]),
            name: "subscript"
        )
        let s2 = s1

        s1.nested.items[1] = 99

        #expect(s1.nested.items == [10, 99, 30])
        #expect(s2.nested.items == [10, 20, 30])
    }
}

extension CoWMacro {
    @Suite struct `Sendable Gating` {
        @Suite struct Unit {}
    }
}

extension CoWMacro.`Sendable Gating`.Unit {

    private static func isSendableType<T>(_ type: T.Type) -> Bool { false }
    private static func isSendableType<T: Sendable>(_ type: T.Type) -> Bool { true }

    @Test
    func `struct without a Sendable declaration is not Sendable`() {
        #expect(!Self.isSendableType(SendableGatingOptedOut.self))
    }

    @Test
    func `struct with an explicit Sendable declaration is Sendable`() {
        #expect(Self.isSendableType(SendableGatingOptedIn.self))
    }
}

private struct NestedModifyCostNaivePoint {
    private final class Storage {
        var x: Int
        init(x: Int) { self.x = x }
        init(copying other: Storage) { self.x = other.x }
    }
    private var storage: Storage
    init(x: Int) { storage = Storage(x: x) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var x: Int {
        _read { yield storage.x }
        _modify {
            ensureUnique()
            yield &storage.x
        }
    }
}

private struct NestedModifyCostNaiveOuter {
    private final class Storage {
        var inner: NestedModifyCostNaivePoint
        init(inner: NestedModifyCostNaivePoint) { self.inner = inner }
        init(copying other: Storage) { self.inner = other.inner }
    }
    private var storage: Storage
    init(inner: NestedModifyCostNaivePoint) { storage = Storage(inner: inner) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var inner: NestedModifyCostNaivePoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            yield &storage.inner
        }
    }
}

@CoW
struct NestedModifyCostMacroInner {
    var x: Int
}

@CoW
struct NestedModifyCostMacroOuter {
    var inner: NestedModifyCostMacroInner
}

private struct NestedModifyCostNaiveArrayPoint {
    private final class Storage {
        var items: [Int]
        init(items: [Int]) { self.items = items }
        init(copying other: Storage) { self.items = other.items }
    }
    private var storage: Storage
    init(items: [Int]) { storage = Storage(items: items) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var items: [Int] {
        _read { yield storage.items }
        _modify {
            ensureUnique()
            yield &storage.items
        }
    }
}

private struct NestedModifyCostNaiveArrayOuter {
    private final class Storage {
        var inner: NestedModifyCostNaiveArrayPoint
        init(inner: NestedModifyCostNaiveArrayPoint) { self.inner = inner }
        init(copying other: Storage) { self.inner = other.inner }
    }
    private var storage: Storage
    init(inner: NestedModifyCostNaiveArrayPoint) { storage = Storage(inner: inner) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var inner: NestedModifyCostNaiveArrayPoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            yield &storage.inner
        }
    }
}

@CoW
struct NestedModifyCostMacroArrayInner {
    var items: [Int]
}

@CoW
struct NestedModifyCostMacroArrayOuter {
    var inner: NestedModifyCostMacroArrayInner
}

private final class CopyCountingCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct CopyCountingPoint {
    fileprivate final class Storage {
        var x: Int
        private let counter: CopyCountingCounter
        init(x: Int, counter: CopyCountingCounter) {
            self.x = x
            self.counter = counter
        }
        init(copying other: Storage) {
            self.x = other.x
            self.counter = other.counter
            self.counter.increment()
        }
    }
    fileprivate var storage: Storage
    init(x: Int, counter: CopyCountingCounter) { storage = Storage(x: x, counter: counter) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var x: Int {
        _read { yield storage.x }
        _modify {
            ensureUnique()
            yield &storage.x
        }
    }
}

private struct CopyCountingDirectYieldOuter {
    private final class Storage {
        var inner: CopyCountingPoint
        init(inner: CopyCountingPoint) { self.inner = inner }
        init(copying other: Storage) { self.inner = other.inner }
    }
    private var storage: Storage
    init(inner: CopyCountingPoint) { storage = Storage(inner: inner) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var inner: CopyCountingPoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            yield &storage.inner
        }
    }
}

private struct CopyCountingCopyOutOuter {
    private final class Storage {
        var inner: CopyCountingPoint
        init(inner: CopyCountingPoint) { self.inner = inner }
        init(copying other: Storage) { self.inner = other.inner }
    }
    private var storage: Storage
    init(inner: CopyCountingPoint) { storage = Storage(inner: inner) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var inner: CopyCountingPoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            var value = storage.inner
            yield &value
            storage.inner = value
        }
    }
}

private struct CopyCountingArrayPoint {
    fileprivate final class Storage {
        var items: [Int]
        private let counter: CopyCountingCounter
        init(items: [Int], counter: CopyCountingCounter) {
            self.items = items
            self.counter = counter
        }
        init(copying other: Storage) {
            self.items = other.items
            self.counter = other.counter
            self.counter.increment()
        }
    }
    fileprivate var storage: Storage
    init(items: [Int], counter: CopyCountingCounter) {
        storage = Storage(items: items, counter: counter)
    }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var items: [Int] {
        _read { yield storage.items }
        _modify {
            ensureUnique()
            yield &storage.items
        }
    }
}

private struct CopyCountingArrayDirectYieldOuter {
    private final class Storage {
        var inner: CopyCountingArrayPoint
        init(inner: CopyCountingArrayPoint) { self.inner = inner }
        init(copying other: Storage) { self.inner = other.inner }
    }
    private var storage: Storage
    init(inner: CopyCountingArrayPoint) { storage = Storage(inner: inner) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var inner: CopyCountingArrayPoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            yield &storage.inner
        }
    }
}

private struct CopyCountingArrayCopyOutOuter {
    private final class Storage {
        var inner: CopyCountingArrayPoint
        init(inner: CopyCountingArrayPoint) { self.inner = inner }
        init(copying other: Storage) { self.inner = other.inner }
    }
    private var storage: Storage
    init(inner: CopyCountingArrayPoint) { storage = Storage(inner: inner) }
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage) }
    }
    var inner: CopyCountingArrayPoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            var value = storage.inner
            yield &value
            storage.inner = value
        }
    }
}

extension CoWMacro {
    @Suite struct `Nested Modify Cost` {
        @Suite struct `Edge Case` {}
    }
}

extension CoWMacro.`Nested Modify Cost` {
    fileprivate static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

extension CoWMacro.`Nested Modify Cost`.`Edge Case` {
    @Test
    func `nested unique mutation spurious inner storage copy count is deterministic`() {
        let iterations = 25

        let directYieldCounter = CopyCountingCounter()
        var directYieldOuter = CopyCountingDirectYieldOuter(
            inner: CopyCountingPoint(x: 0, counter: directYieldCounter)
        )
        (0..<iterations).forEach { i in directYieldOuter.inner.x = i }
        #expect(directYieldOuter.inner.x == iterations - 1)
        #expect(
            directYieldCounter.count == 0,
            """
            direct-yield _modify (matching the current, post-F-002 macro shape) forced \
            \(directYieldCounter.count) spurious inner-storage copies over \(iterations) \
            uniquely-referenced nested mutations; expected 0
            """
        )

        let copyOutCounter = CopyCountingCounter()
        var copyOutOuter = CopyCountingCopyOutOuter(
            inner: CopyCountingPoint(x: 0, counter: copyOutCounter)
        )
        (0..<iterations).forEach { i in copyOutOuter.inner.x = i }
        #expect(copyOutOuter.inner.x == iterations - 1)
        #expect(
            copyOutCounter.count == iterations,
            """
            copy-out _modify (matching the removed, pre-F-002 macro shape) forced \
            \(copyOutCounter.count) spurious inner-storage copies over \(iterations) \
            uniquely-referenced nested mutations; expected exactly \(iterations) (one per \
            mutation), confirming this fixture reproduces the mechanism the fix removed
            """
        )
    }

    @Test
    func `nested unique mutation timing vs a naive baseline is informational only`() {
        let iterations = 50_000
        let clock = ContinuousClock()

        var warmupNaive = NestedModifyCostNaiveOuter(inner: NestedModifyCostNaivePoint(x: 0))
        (0..<2_000).forEach { i in warmupNaive.inner.x = i }
        var warmupMacro = NestedModifyCostMacroOuter(inner: NestedModifyCostMacroInner(x: 0))
        (0..<2_000).forEach { i in warmupMacro.inner.x = i }

        var naiveResult = 0
        let naiveDuration = clock.measure {
            var outer = NestedModifyCostNaiveOuter(inner: NestedModifyCostNaivePoint(x: 0))
            for i in 0..<iterations { outer.inner.x = i }
            naiveResult = outer.inner.x
        }
        #expect(naiveResult == iterations - 1)

        var macroResult = 0
        let macroDuration = clock.measure {
            var outer = NestedModifyCostMacroOuter(inner: NestedModifyCostMacroInner(x: 0))
            for i in 0..<iterations { outer.inner.x = i }
            macroResult = outer.inner.x
        }
        #expect(macroResult == iterations - 1)

        let ratio =
            CoWMacro.`Nested Modify Cost`.seconds(macroDuration)
            / CoWMacro.`Nested Modify Cost`.seconds(naiveDuration)
        print(
            "[informational] nested unique mutation: macro-generated took \(ratio)x the naive baseline"
        )
    }

    @Test
    func
        `nested collection append spurious inner storage copy count scales linearly not quadratically`()
    {

        for iterations in [25, 100] {
            let directYieldCounter = CopyCountingCounter()
            var directYieldOuter = CopyCountingArrayDirectYieldOuter(
                inner: CopyCountingArrayPoint(items: [], counter: directYieldCounter)
            )
            (0..<iterations).forEach { i in directYieldOuter.inner.items.append(i) }
            #expect(directYieldOuter.inner.items.count == iterations)
            #expect(
                directYieldCounter.count == 0,
                """
                direct-yield _modify (matching the current, post-F-002 macro shape) forced \
                \(directYieldCounter.count) spurious inner-storage copies over \(iterations) \
                uniquely-referenced nested appends; expected 0
                """
            )

            let copyOutCounter = CopyCountingCounter()
            var copyOutOuter = CopyCountingArrayCopyOutOuter(
                inner: CopyCountingArrayPoint(items: [], counter: copyOutCounter)
            )
            (0..<iterations).forEach { i in copyOutOuter.inner.items.append(i) }
            #expect(copyOutOuter.inner.items.count == iterations)
            #expect(
                copyOutCounter.count == iterations,
                """
                copy-out _modify (matching the removed, pre-F-002 macro shape) forced \
                \(copyOutCounter.count) spurious inner-storage copies over \(iterations) \
                uniquely-referenced nested appends; expected exactly \(iterations) (one per \
                append, each copying the whole O(current size) buffer), confirming this \
                fixture reproduces the O(n^2) mechanism the fix removed
                """
            )
        }
    }

    @Test
    func `nested collection append timing vs a naive baseline is informational only`() {
        let iterations = 4_000
        let clock = ContinuousClock()

        var warmupNaive = NestedModifyCostNaiveArrayOuter(
            inner: NestedModifyCostNaiveArrayPoint(items: [])
        )
        (0..<200).forEach { i in warmupNaive.inner.items.append(i) }
        var warmupMacro = NestedModifyCostMacroArrayOuter(
            inner: NestedModifyCostMacroArrayInner(items: [])
        )
        (0..<200).forEach { i in warmupMacro.inner.items.append(i) }

        var naiveCount = 0
        let naiveDuration = clock.measure {
            var outer = NestedModifyCostNaiveArrayOuter(
                inner: NestedModifyCostNaiveArrayPoint(items: [])
            )
            for i in 0..<iterations { outer.inner.items.append(i) }
            naiveCount = outer.inner.items.count
        }
        #expect(naiveCount == iterations)

        var macroCount = 0
        let macroDuration = clock.measure {
            var outer = NestedModifyCostMacroArrayOuter(
                inner: NestedModifyCostMacroArrayInner(items: [])
            )
            for i in 0..<iterations { outer.inner.items.append(i) }
            macroCount = outer.inner.items.count
        }
        #expect(macroCount == iterations)

        let ratio =
            CoWMacro.`Nested Modify Cost`.seconds(macroDuration)
            / CoWMacro.`Nested Modify Cost`.seconds(naiveDuration)
        print(
            "[informational] nested collection append: macro-generated took \(ratio)x the naive baseline"
        )
    }
}
