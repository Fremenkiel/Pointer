import Geometry
import Model

extension StrokeStore {
    /// The draw data of one stroke: plain values only, so the per-frame loop copies no
    /// references and does no reference counting (PERF-01).
    ///
    /// The stored fields take 48 bytes per stroke: 32-bit indices and the size class of the
    /// block instead of its capacity. The M2 layout took 80 bytes (docs/m2-fix-plan.md, phase
    /// 4, task 5).
    struct DrawInfo {
        let origin: Point
        var lastDrawnFrame: UInt64 = 0
        let radius: Float
        private let storedPointCount: Int32
        private var storedFirstBlock: Int32
        private var blockStart: Int32 = -1
        private var storedResidentIndex: Int32 = -1
        private let storedBlockCount: UInt16
        private var blockClass: UInt8 = 0
        /// The marks of the stroke, one bit each, so the fields stay at 48 bytes.
        private var flags: UInt8 = 0

        /// The bit of `isReferenced`.
        private static let referencedFlag: UInt8 = 1
        /// The bit of `isRemoved`.
        private static let removedFlag: UInt8 = 2

        /// `true` after a draw. The clock sweep clears it once before it evicts the stroke.
        var isReferenced: Bool {
            get { flags & Self.referencedFlag != 0 }
            set { flags = newValue ? flags | Self.referencedFlag : flags & ~Self.referencedFlag }
        }

        /// `true` after `remove(_:frame:)`, until the slot holds a new stroke.
        var isRemoved: Bool {
            get { flags & Self.removedFlag != 0 }
            set { flags = newValue ? flags | Self.removedFlag : flags & ~Self.removedFlag }
        }

        /// Makes the draw data of a stroke without a block.
        ///
        /// - Precondition: The values fit into the stored fields.
        init(origin: Point, radius: Float, pointCount: Int, firstBlock: Int, blockCount: Int) {
            precondition(pointCount >= 2 && pointCount <= Limits.maxPointsPerStroke, "Bad count")
            precondition(firstBlock >= 0 && firstBlock <= Int(Int32.max), "Block index too large")
            precondition(blockCount >= 1 && blockCount <= Int(UInt16.max), "Bad block count")
            self.origin = origin
            self.radius = radius
            storedPointCount = Int32(pointCount)
            storedFirstBlock = Int32(firstBlock)
            storedBlockCount = UInt16(blockCount)
        }

        /// The control points of the stroke.
        var pointCount: Int { Int(storedPointCount) }
        /// The index of the first block spacing of the stroke in `blockSpacings`. A compaction
        /// of the block lists moves it (M-04).
        var firstBlock: Int {
            get { Int(storedFirstBlock) }
            set {
                precondition(newValue >= 0 && newValue <= Int(Int32.max), "Bad first block")
                storedFirstBlock = Int32(newValue)
            }
        }
        /// The number of blocks of the stroke (`DetailRuns`).
        var blockCount: Int { Int(storedBlockCount) }

        /// The arena block of the stroke, or `nil` if its points are not in the arena.
        var block: ArenaBlock? {
            get {
                guard blockStart >= 0 else { return nil }
                let capacity = SlabAllocator.classPoints(Int(blockClass))
                return ArenaBlock(start: Int(blockStart), capacity: capacity)
            }
            set {
                guard let newValue else {
                    blockStart = -1
                    return
                }
                precondition(newValue.start <= Int(Int32.max), "Block \(newValue) is too far")
                blockStart = Int32(newValue.start)
                blockClass = UInt8(SlabAllocator.classIndex(forPoints: newValue.capacity))
                assert(block == newValue, "The stored block differs from \(newValue)")
            }
        }

        /// The index of the stroke in `residentSlots`, or -1 if the stroke has no block.
        var residentIndex: Int {
            get { Int(storedResidentIndex) }
            set {
                precondition(newValue >= -1 && newValue <= Int(Int32.max), "Bad index")
                storedResidentIndex = Int32(newValue)
            }
        }
    }
}
