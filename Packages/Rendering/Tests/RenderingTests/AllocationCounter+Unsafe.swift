import Darwin
import Synchronization

/// The signature of the `malloc_logger` hook of libmalloc.
private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

/// The allocations since the last start of a count.
private let allocationCount = Atomic<Int>(0)

/// The `malloc_logger` type flag of an allocation.
private let allocationFlag: UInt32 = 2

/// `true` while a count takes only the allocations of the main thread.
private let countsMainThreadOnly = Atomic<Bool>(false)

/// Counts heap allocations through the `malloc_logger` hook of libmalloc (PERF-01).
///
/// The count covers every thread of the process while the body runs, so it also holds the
/// allocations inside Metal (D-43).
enum AllocationCounter {
    /// Runs `body` and returns the heap allocations of the process during the run.
    ///
    /// - Precondition: No other count runs at the same time.
    /// - Returns: The count, or `nil` if the process has no `malloc_logger` symbol.
    static func count(_ body: () -> Void) -> Int? {
        countsMainThreadOnly.store(false, ordering: .relaxed)
        return countAll(body)
    }

    /// Runs `body` and returns the heap allocations of the main thread during the run. A test of
    /// a main-thread path uses it, so that the threads of Metal and the system do not count.
    ///
    /// - Precondition: No other count runs at the same time.
    /// - Returns: The count, or `nil` if the process has no `malloc_logger` symbol.
    static func countMainThread(_ body: () -> Void) -> Int? {
        countsMainThreadOnly.store(true, ordering: .relaxed)
        defer { countsMainThreadOnly.store(false, ordering: .relaxed) }
        return countAll(body)
    }

    private static func countAll(_ body: () -> Void) -> Int? {
        // Safe: RTLD_DEFAULT is the documented pseudo handle -2. The symbol is a global function
        // pointer of libmalloc that holds `MallocLogger?`. Only this function writes it, and
        // the tests call it from one thread at a time: the render thread of the frame-loop test.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
            body()
            return nil
        }
        let hook = symbol.assumingMemoryBound(to: MallocLogger?.self)
        assert(hook.pointee == nil, "Another tool already uses malloc_logger")
        allocationCount.store(0, ordering: .relaxed)
        hook.pointee = { type, _, _, _, _, _ in
            guard type & allocationFlag != 0 else { return }
            // Safe: pthread_main_np reads the thread of the caller and allocates nothing.
            guard !countsMainThreadOnly.load(ordering: .relaxed) || pthread_main_np() != 0 else {
                return
            }
            allocationCount.add(1, ordering: .relaxed)
        }
        body()
        hook.pointee = nil
        return allocationCount.load(ordering: .relaxed)
    }
}
