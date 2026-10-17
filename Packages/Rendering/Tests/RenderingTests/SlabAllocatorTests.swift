import Testing

@testable import Rendering

@Suite("Slab allocator")
struct SlabAllocatorTests {
    @Test(
        "A stroke gets the smallest class that holds it",
        arguments: [(1, 16), (16, 16), (17, 32), (300, 512), (16_384, 16_384)]
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
        for _ in 0..<(SlabAllocator.slabPoints / 1024) {
            let allocated1 = allocator.allocate(points: 1000)

            let block = try #require(allocated1)
            #expect(block.start % 1024 == 0)
            starts.insert(block.start)
        }
        #expect(starts.count == SlabAllocator.slabPoints / 1024)
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
        let allocated4 = allocator.allocate(points: 8192)

        let first = try #require(allocated4)
        let allocated6 = allocator.allocate(points: 8192)

        #expect(allocated6 != nil)
        let allocated10 = allocator.allocate(points: 8192)

        #expect(allocated10 == nil)
        allocator.free(first)
        let allocated11 = allocator.allocate(points: 8192)

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
}
