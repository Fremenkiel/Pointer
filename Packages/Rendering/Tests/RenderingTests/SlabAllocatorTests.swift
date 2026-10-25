import Testing

@testable import Rendering

@Suite("Slab allocator")
struct SlabAllocatorTests {
    @Test(
        "A stroke gets the smallest class that holds it",
        arguments: [(1, 16), (16, 16), (17, 32), (300, 304), (1_000, 1_120), (16_384, 16_384)]
    )
    func classes(points: Int, capacity: Int) throws {
        var allocator = SlabAllocator(slabCount: 1)
        let allocated = allocator.allocate(points: points)
        let block = try #require(allocated)
        #expect(block.capacity == capacity)
        #expect(allocator.usedPoints == capacity)
    }

    @Test("Blocks of one class fill a slab without overlap")
    func noOverlap() throws {
        var allocator = SlabAllocator(slabCount: 1)
        var starts = Set<Int>()
        let capacity = SlabAllocator.classPoints(SlabAllocator.classIndex(forPoints: 1000))
        let perSlab = SlabAllocator.slabPoints / capacity
        for _ in 0..<perSlab {
            let allocated = allocator.allocate(points: 1000)
            let block = try #require(allocated)
            #expect(block.start % capacity == 0)
            starts.insert(block.start)
        }
        #expect(starts.count == perSlab)
        let allocated8 = allocator.allocate(points: 1000)

        #expect(allocated8 == nil)
    }

    @Test("A freed slab serves another class")
    func reuse() throws {
        var allocator = SlabAllocator(slabCount: 1)
        let allocated2 = allocator.allocate(points: 10)

        let small = try #require(allocated2)
        let allocated9 = allocator.allocate(points: 16_384)

        #expect(allocated9 == nil)
        allocator.free(small)
        #expect(allocator.usedPoints == 0)
        let allocated3 = allocator.allocate(points: 16_384)

        let large = try #require(allocated3)
        #expect(large.start == 0)
    }

    @Test("A full slab takes blocks again after a free")
    func refill() throws {
        var allocator = SlabAllocator(slabCount: 1)
        let capacity = SlabAllocator.classPoints(SlabAllocator.classIndex(forPoints: 4000))
        let perSlab = SlabAllocator.slabPoints / capacity
        let allocated4 = allocator.allocate(points: 4000)
        let first = try #require(allocated4)
        for _ in 1..<perSlab {
            let allocated6 = allocator.allocate(points: 4000)
            #expect(allocated6 != nil)
        }
        let allocated10 = allocator.allocate(points: 4000)
        #expect(allocated10 == nil)
        allocator.free(first)
        let allocated11 = allocator.allocate(points: 4000)
        #expect(allocated11 == first)
    }

    @Test("Added slabs extend the arena")
    func grow() throws {
        var allocator = SlabAllocator(slabCount: 1)
        let allocated7 = allocator.allocate(points: 16_384)

        #expect(allocated7 != nil)
        allocator.addSlabs(1)
        let allocated5 = allocator.allocate(points: 16_384)

        let block = try #require(allocated5)
        #expect(block.start == SlabAllocator.slabPoints)
        #expect(allocator.slabCount == 2)
    }

    @Test(
        "The slabs of a pass hold all its blocks, and less than the worst case of all classes",
        arguments: [[60], [300, 300, 1_000], [16_384, 1, 17, 60, 300]]
    )
    func slabsOfPass(pattern: [Int]) throws {
        let counts = (0..<2_000).map { pattern[$0 % pattern.count] }
        let slabs = SlabAllocator.slabsNeeded(pointCounts: counts)
        var allocator = SlabAllocator(slabCount: slabs)
        for points in counts {
            let block = allocator.allocate(points: points)
            #expect(block != nil, "A block of \(points) points fits")
        }
        let points = counts.reduce(0, +)
        let worst = (points * 2) / SlabAllocator.slabPoints + SlabAllocator.classCount + 1
        #expect(slabs < worst, "\(slabs) slabs against \(worst)")
    }
}
