import Metal
import QuartzCore
import Synchronization

/// The presented handler of the handoff frames (the M10 plan task 3.6). A closure that captured
/// the handoff number cost two allocations per handoff frame: its context, and the block that
/// Swift made of it. The handler here captures nothing, so only the block is left. It finds the
/// handoff of a drawable by the identity of the drawable in a table of the process, because the
/// drawables of all layers share the table.
enum PresentedHandoffs {
    /// One handoff that waits for its drawable.
    private struct Entry {
        var drawable: ObjectIdentifier?
        var handoff: UInt64 = 0
        var onPresented: (@Sendable (UInt64) -> Void)?
    }

    /// The handoffs in flight: three drawables per layer, for the parent and the child of a
    /// flight and the offscreen previews, with room to spare.
    static let capacity = 16

    private static let entries = Mutex<[Entry]>(Array(repeating: Entry(), count: capacity))

    /// Calls `onPresented` with `handoff` when `drawable` is presented. With all slots in use,
    /// a closure of its own carries the handoff.
    ///
    /// - Precondition: `handoff` is positive.
    static func attach(
        _ handoff: UInt64,
        to drawable: any CAMetalDrawable,
        onPresented: @escaping @Sendable (UInt64) -> Void
    ) {
        precondition(handoff > 0, "Handoffs count from 1")
        let id = ObjectIdentifier(drawable)
        let isRecorded = entries.withLock { slots in
            guard let free = slots.firstIndex(where: { $0.drawable == nil }) else { return false }
            slots[free] = Entry(drawable: id, handoff: handoff, onPresented: onPresented)
            return true
        }
        guard isRecorded else {
            drawable.addPresentedHandler { _ in onPresented(handoff) }
            return
        }
        drawable.addPresentedHandler { presented in Self.present(ObjectIdentifier(presented)) }
    }

    /// Calls the callback of the handoff of a presented drawable and frees its slot.
    private static func present(_ drawable: ObjectIdentifier) {
        let entry = entries.withLock { slots -> Entry? in
            guard let index = slots.firstIndex(where: { $0.drawable == drawable }) else {
                return nil
            }
            defer { slots[index] = Entry() }
            return slots[index]
        }
        guard let entry, let onPresented = entry.onPresented else { return }
        onPresented(entry.handoff)
    }
}
