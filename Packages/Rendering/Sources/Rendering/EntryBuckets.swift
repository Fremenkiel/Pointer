/// The draw entries of one ink pass, one list per arena buffer (docs/m2-fix-plan.md, phase 4,
/// task 3).
///
/// A pass works on a local copy, because the per-entry access to a class property costs a
/// run-time exclusivity check. The lists keep their capacity, so a pass allocates nothing once
/// they have grown (PERF-01).
struct EntryBuckets {
    /// The entries of each buffer, in drawing order.
    private(set) var lists: [[StrokeDrawEntry]] = []
    /// The instances of each list.
    private(set) var instances: [Int] = []
    /// The entries of all lists.
    private(set) var entryCount = 0

    /// Empties all lists and makes one list per buffer.
    mutating func reset(bufferCount: Int) {
        precondition(bufferCount >= 0, "Buffer count \(bufferCount) is negative")
        ensure(bufferCount: bufferCount)
        for index in lists.indices {
            lists[index].removeAll(keepingCapacity: true)
            instances[index] = 0
        }
        entryCount = 0
        assert(lists.count == instances.count, "Each list has an instance count")
    }

    /// Adds lists until there is one per buffer. A load can add a buffer during a pass.
    mutating func ensure(bufferCount: Int) {
        guard lists.count < bufferCount else { return }
        lists.append(contentsOf: repeatElement([], count: bufferCount - lists.count))
        instances.append(contentsOf: repeatElement(0, count: bufferCount - instances.count))
        assert(lists.count == bufferCount, "One list per buffer")
    }

    /// The instances of one list so far.
    func instanceCount(of bucket: Int) -> Int {
        instances[bucket]
    }

    /// Adds an entry with `instanceCount` instances to the list of a buffer.
    ///
    /// - Precondition: The list exists, and the entry draws one instance at least.
    mutating func append(_ entry: StrokeDrawEntry, instanceCount: Int, to bucket: Int) {
        precondition(lists.indices.contains(bucket), "Bucket \(bucket) does not exist")
        precondition(instanceCount > 0, "An entry draws one instance at least")
        lists[bucket].append(entry)
        instances[bucket] += instanceCount
        entryCount += 1
    }
}
