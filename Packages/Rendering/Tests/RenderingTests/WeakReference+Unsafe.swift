/// A weak reference that a test fills inside the lock of an engine and reads after the lock.
///
/// Safe as `@unchecked Sendable`: the test writes it once inside `withRenderer`, which runs on
/// the calling thread, and reads it later on the same actor. The reference is weak, so the box
/// never keeps the object.
final class WeakReference<Object: AnyObject>: @unchecked Sendable {
    weak var object: Object?
}
