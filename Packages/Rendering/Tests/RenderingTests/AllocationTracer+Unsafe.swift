import Darwin
import Synchronization

/// The signature of the `malloc_logger` hook of libmalloc.
private typealias TraceLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

/// The `malloc_logger` type flag of an allocation.
private let traceAllocationFlag: UInt32 = 2
/// The most allocations that one trace keeps, and the most frames of each stack.
private let maxTraces = 256
private let framesPerTrace = 32
/// The allocations of the main thread since the start of a trace.
private let traceIndex = Atomic<Int>(0)
/// `true` while the hook records a stack, so an allocation inside the record does not recurse.
private let isRecording = Atomic<Bool>(false)
// Safe: allocated once and never freed. Only the hook writes them, on the main thread during one
// trace, and `trace` reads them after it removes the hook.
nonisolated(unsafe) private let traceFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>
    .allocate(capacity: maxTraces * framesPerTrace)
nonisolated(unsafe) private let traceDepths = UnsafeMutablePointer<Int32>.allocate(
    capacity: maxTraces
)

/// Counts the heap allocations of the main thread by the code that asks for them (PERF-01,
/// D-43, the M8 fix plan section 3).
///
/// The hook records the call stack of each allocation with `backtrace`, into buffers made before
/// the trace. After the run, the first caller above malloc and the runtime libraries decides: an
/// image of Pointer makes a Pointer allocation, and UIKit, Core Animation, or Metal make system
/// work, which does not count (D-43).
enum AllocationTracer {
    /// The allocations of one run.
    struct Result {
        /// The allocations that Pointer code asked for.
        let pointer: Int
        /// The allocations that UIKit, Core Animation, or Metal asked for.
        let system: Int
        /// The allocations past `maxTraces`, which the trace could not attribute.
        let unrecorded: Int
        /// The image and the symbol that decided each Pointer allocation, for a failure message.
        var pointerCallers: [String] = []
    }

    /// Runs `body` and attributes the heap allocations of the main thread during the run.
    ///
    /// - Precondition: No other count or trace runs at the same time.
    /// - Returns: The counts, or `nil` if the process has no `malloc_logger` symbol.
    static func trace(_ body: () -> Void) -> Result? {
        // Safe: RTLD_DEFAULT is the documented pseudo handle -2, and the symbol is the global
        // function pointer of libmalloc, as in AllocationCounter.
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else {
            body()
            return nil
        }
        let hook = symbol.assumingMemoryBound(to: TraceLogger?.self)
        assert(hook.pointee == nil, "Another tool already uses malloc_logger")
        traceIndex.store(0, ordering: .relaxed)
        // The first call binds the symbol, which can allocate, so it runs before the hook.
        _ = backtrace(traceFrames, Int32(framesPerTrace))
        hook.pointee = { type, _, _, _, _, _ in
            guard type & traceAllocationFlag != 0, pthread_main_np() != 0 else { return }
            guard !isRecording.exchange(true, ordering: .relaxed) else { return }
            defer { isRecording.store(false, ordering: .relaxed) }
            let index = traceIndex.add(1, ordering: .relaxed).oldValue
            guard index < maxTraces else { return }
            traceDepths[index] = backtrace(
                traceFrames + index * framesPerTrace,
                Int32(framesPerTrace)
            )
        }
        body()
        hook.pointee = nil
        let total = traceIndex.load(ordering: .relaxed)
        let recorded = min(total, maxTraces)
        let pointer = (0..<recorded).filter(isPointerAllocation)
        return Result(
            pointer: pointer.count,
            system: recorded - pointer.count,
            unrecorded: total - recorded,
            pointerCallers: pointer.map(caller)
        )
    }

    /// The images that both Pointer and the system call: malloc, the runtimes, Foundation, and
    /// the text and drawing libraries, with UIFoundation, the TextKit of `UITextView`. A frame
    /// there does not decide, so the walk goes on to its caller. Without UIFoundation, the redraw
    /// that UIKit makes of a scaled text view counted as about 31 Pointer allocations per frame.
    private static let passThroughImages: Set<String> = [
        "libsystem_malloc.dylib", "libobjc.A.dylib", "libswiftCore.dylib", "Foundation",
        "CoreFoundation", "libdispatch.dylib", "libsystem_platform.dylib", "CoreText",
        "CoreGraphics", "UIFoundation", "libc++abi.dylib", "libsystem_blocks.dylib",
    ]
    /// The images of system work that does not count: UIKit, Core Animation, and Metal (D-43).
    /// The Metal work includes the GPU driver and the frame pacing of the display link.
    private static let systemImages: Set<String> = [
        "UIKitCore", "QuartzCore", "Metal", "FramePacing",
    ]
    /// The name starts of the GPU driver images, whose names hold the GPU family.
    private static let systemImagePrefixes = ["AGXMetal", "IOGPU"]

    /// Whether the allocation at `index` comes from Pointer code. The first frame is the hook.
    private static func isPointerAllocation(_ index: Int) -> Bool {
        let depth = Int(traceDepths[index])
        for frame in 1..<max(depth, 1) {
            let image = imageName(traceFrames[index * framesPerTrace + frame])
            if isSystem(image) { return false }
            if !passThroughImages.contains(image) { return true }
        }
        // A stack of runtime frames only has no caller to blame, so it counts.
        return true
    }

    private static func isSystem(_ image: String) -> Bool {
        systemImages.contains(image) || systemImagePrefixes.contains { image.hasPrefix($0) }
    }

    /// Returns the image and the symbol of the frame that decided the allocation at `index`.
    private static func caller(_ index: Int) -> String {
        let depth = Int(traceDepths[index])
        for frame in 1..<max(depth, 1) {
            let address = traceFrames[index * framesPerTrace + frame]
            let image = imageName(address)
            guard passThroughImages.contains(image) else {
                var info = Dl_info()
                let symbol =
                    address.flatMap { dladdr($0, &info) != 0 ? info.dli_sname : nil }
                    .map { String(cString: $0) } ?? "?"
                return "\(image) \(symbol)"
            }
        }
        return "runtime only"
    }

    /// Returns the file name of the image that holds `address`.
    private static func imageName(_ address: UnsafeMutableRawPointer?) -> String {
        var info = Dl_info()
        guard let address, dladdr(address, &info) != 0, let path = info.dli_fname else {
            return ""
        }
        return String(cString: path).split(separator: "/").last.map(String.init) ?? ""
    }
}
