import Copy_on_Write
import Testing

struct NaivePoint {
    private final class Storage: @unchecked Sendable {
        var x: Int
        var y: Int

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
        init(copying other: Storage) {
            self.x = other.x
            self.y = other.y
        }
    }

    private var storage: Storage

    init(x: Int, y: Int) { storage = Storage(x: x, y: y) }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(copying: storage)
        }
    }

    var x: Int {
        _read { yield storage.x }
        _modify {
            ensureUnique()
            yield &storage.x
        }
    }

    var y: Int {
        _read { yield storage.y }
        _modify {
            ensureUnique()
            yield &storage.y
        }
    }
}

struct NaiveOuter {
    private final class Storage: @unchecked Sendable {
        var inner: NaivePoint
        var label: Int

        init(inner: NaivePoint, label: Int) {
            self.inner = inner
            self.label = label
        }
        init(copying other: Storage) {
            self.inner = other.inner
            self.label = other.label
        }
    }

    private var storage: Storage

    init(inner: NaivePoint, label: Int) { storage = Storage(inner: inner, label: label) }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(copying: storage)
        }
    }

    var inner: NaivePoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            yield &storage.inner
        }
    }

    var label: Int {
        _read { yield storage.label }
        _modify {
            ensureUnique()
            yield &storage.label
        }
    }
}

struct SafePoint {
    private final class Storage: @unchecked Sendable {
        var x: Int
        var y: Int

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
        init(copying other: Storage) {
            self.x = other.x
            self.y = other.y
        }
    }

    private var storage: Storage

    init(x: Int, y: Int) { storage = Storage(x: x, y: y) }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(copying: storage)
        }
    }

    var x: Int {
        _read { yield storage.x }
        _modify {
            ensureUnique()
            var value = storage.x
            yield &value
            storage.x = value
        }
    }

    var y: Int {
        _read { yield storage.y }
        _modify {
            ensureUnique()
            var value = storage.y
            yield &value
            storage.y = value
        }
    }
}

struct SafeOuter {
    private final class Storage: @unchecked Sendable {
        var inner: SafePoint
        var label: Int

        init(inner: SafePoint, label: Int) {
            self.inner = inner
            self.label = label
        }
        init(copying other: Storage) {
            self.inner = other.inner
            self.label = other.label
        }
    }

    private var storage: Storage

    init(inner: SafePoint, label: Int) { storage = Storage(inner: inner, label: label) }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = Storage(copying: storage)
        }
    }

    var inner: SafePoint {
        _read { yield storage.inner }
        _modify {
            ensureUnique()
            var value = storage.inner
            yield &value
            storage.inner = value
        }
    }

    var label: Int {
        _read { yield storage.label }
        _modify {
            ensureUnique()
            var value = storage.label
            yield &value
            storage.label = value
        }
    }
}

@CoW
struct MacroInner {
    var x: Int
    var y: Int
}

@CoW
struct MacroOuter {
    var inner: MacroInner
    var label: Int
}

private let iterations = 100_000

@Suite(.serialized)
struct ModifyPerformanceTests {

    @Test(.timed(threshold: .milliseconds(50)))
    func `naive single-level unique mutation`() {
        var point = NaivePoint(x: 0, y: 0)
        for i in 0..<iterations {
            point.x = i
        }
        #expect(point.x == iterations - 1)
    }

    @Test(.timed(threshold: .milliseconds(50)))
    func `safe single-level unique mutation`() {
        var point = SafePoint(x: 0, y: 0)
        for i in 0..<iterations {
            point.x = i
        }
        #expect(point.x == iterations - 1)
    }

    @Test(.timed(threshold: .milliseconds(200)))
    func `naive single-level shared mutation`() {
        var point = NaivePoint(x: 0, y: 0)
        var copies: [NaivePoint] = []
        for i in 0..<iterations {
            let copy = point
            point.x = i
            copies.append(copy)
        }
        #expect(point.x == iterations - 1)
        #expect(copies.count == iterations)
    }

    @Test(.timed(threshold: .milliseconds(200)))
    func `safe single-level shared mutation`() {
        var point = SafePoint(x: 0, y: 0)
        var copies: [SafePoint] = []
        for i in 0..<iterations {
            let copy = point
            point.x = i
            copies.append(copy)
        }
        #expect(point.x == iterations - 1)
        #expect(copies.count == iterations)
    }

    @Test(.timed(threshold: .milliseconds(50)))
    func `naive nested unique mutation`() {
        var outer = NaiveOuter(inner: NaivePoint(x: 0, y: 0), label: 0)
        for i in 0..<iterations {
            outer.inner.x = i
        }
        #expect(outer.inner.x == iterations - 1)
    }

    @Test(.timed(threshold: .milliseconds(50)))
    func `safe nested unique mutation`() {
        var outer = SafeOuter(inner: SafePoint(x: 0, y: 0), label: 0)
        for i in 0..<iterations {
            outer.inner.x = i
        }
        #expect(outer.inner.x == iterations - 1)
    }

    @Test(.timed(threshold: .milliseconds(200)))
    func `naive nested shared mutation`() {
        var outer = NaiveOuter(inner: NaivePoint(x: 0, y: 0), label: 0)
        var copies: [NaiveOuter] = []
        for i in 0..<iterations {
            let copy = outer
            outer.inner.x = i
            copies.append(copy)
        }
        #expect(outer.inner.x == iterations - 1)
        #expect(copies.count == iterations)
    }

    @Test(.timed(threshold: .milliseconds(200)))
    func `safe nested shared mutation`() {
        var outer = SafeOuter(inner: SafePoint(x: 0, y: 0), label: 0)
        var copies: [SafeOuter] = []
        for i in 0..<iterations {
            let copy = outer
            outer.inner.x = i
            copies.append(copy)
        }
        #expect(outer.inner.x == iterations - 1)
        #expect(copies.count == iterations)
    }

    @Test(.timed(threshold: .milliseconds(50)))
    func `naive read-only access`() {
        let outer = NaiveOuter(inner: NaivePoint(x: 42, y: 7), label: 1)
        var sum = 0
        for _ in 0..<iterations {
            sum &+= outer.inner.x
        }
        #expect(sum == 42 &* iterations)
    }

    @Test(.timed(threshold: .milliseconds(50)))
    func `safe read-only access`() {
        let outer = SafeOuter(inner: SafePoint(x: 42, y: 7), label: 1)
        var sum = 0
        for _ in 0..<iterations {
            sum &+= outer.inner.x
        }
        #expect(sum == 42 &* iterations)
    }

    @Test(.timed(threshold: .milliseconds(50)))
    func `macro-generated nested unique mutation`() {
        var outer = MacroOuter(inner: MacroInner(x: 0, y: 0), label: 0)
        for i in 0..<iterations {
            outer.inner.x = i
        }
        #expect(outer.inner.x == iterations - 1)
    }
}
