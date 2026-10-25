/// The bytes that a collection holds for its elements, from its capacity (D-167).
///
/// A test of a memory budget sums these counts, because the heap growth of a build also holds
/// the unused rest of the blocks that libmalloc gives back. That rest depends on the blocks that
/// earlier code freed. The counts leave out the fixed header of each storage object.
extension Array {
    /// The bytes of the element storage: the capacity times the stride of an element.
    public var storageByteCount: Int {
        let bytes = capacity * MemoryLayout<Element>.stride
        return bytes
    }
}

extension Dictionary {
    /// The bytes of the hash table: one key and one value per bucket, and one bit per bucket for
    /// the bucket map. A native dictionary holds at most three entries per four buckets, and its
    /// bucket count is a power of two.
    public var storageByteCount: Int {
        guard capacity > 0 else { return 0 }
        let buckets = Self.bucketCount(capacity: capacity)
        let words = (buckets + Int.bitWidth - 1) / Int.bitWidth
        let entry = MemoryLayout<Key>.stride + MemoryLayout<Value>.stride
        let bytes = buckets * entry + words * MemoryLayout<Int>.stride
        assert(bytes >= count * entry, "The table holds each entry")
        return bytes
    }

    /// The smallest power of two of buckets that holds `capacity` entries at the load factor of
    /// three quarters.
    ///
    /// - Precondition: `capacity` is greater than zero.
    static func bucketCount(capacity: Int) -> Int {
        precondition(capacity > 0, "A table with buckets holds an entry, got \(capacity)")
        var buckets = 2
        for _ in 0..<(Int.bitWidth - 2) where buckets * 3 / 4 < capacity {
            buckets <<= 1
        }
        assert(buckets * 3 / 4 >= capacity, "\(buckets) buckets hold \(capacity) entries")
        return buckets
    }
}
