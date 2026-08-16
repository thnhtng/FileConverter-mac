import Foundation

/// A tiny lock-protected mutable box, used to accumulate state from
/// non-actor-isolated callbacks (e.g. `FileHandle.readabilityHandler`, which
/// runs on an arbitrary GCD queue) without tripping Swift's strict
/// concurrency data-race checks on captured `var`s.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
