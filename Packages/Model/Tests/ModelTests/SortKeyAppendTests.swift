import Testing

@testable import Model

/// The keys of long appends and prepends (D-182, the M10 plan task 6.3). Before D-182, the keys of
/// appends at one end reached `Limits.maxSortKeyLength` after 3,874 keys.
@Suite("Sort key appends")
struct SortKeyAppendTests {
    @Test("1,000,000 appends at the end stay in order and short")
    func appends() throws {
        var last = try FractionalIndex.between(nil, nil)
        var longest = last.rawValue.utf8.count
        for _ in 0..<1_000_000 {
            let next = try FractionalIndex.between(last, nil)
            #expect(last < next, "\(next.rawValue) after \(last.rawValue)")
            longest = max(longest, next.rawValue.utf8.count)
            last = next
        }
        #expect(longest <= FractionalIndex.stepWidth + 1, "Longest key \(longest)")
    }

    @Test("100,000 prepends at the start stay in order and short")
    func prepends() throws {
        var first = try FractionalIndex.between(nil, nil)
        var longest = first.rawValue.utf8.count
        for _ in 0..<100_000 {
            let next = try FractionalIndex.between(nil, first)
            #expect(next < first, "\(next.rawValue) before \(first.rawValue)")
            longest = max(longest, next.rawValue.utf8.count)
            first = next
        }
        #expect(longest <= FractionalIndex.stepWidth + 1, "Longest key \(longest)")
    }

    @Test(
        "A step at the ends keeps the order of keys of each length",
        arguments: ["1", "01", "V", "zzzz", "zzzzz", "V0Z5K", "0001", "000000001"]
    )
    func ends(key: String) throws {
        let middle = try FractionalIndex(rawValue: key)
        let after = try FractionalIndex.between(middle, nil)
        let before = try FractionalIndex.between(nil, middle)
        #expect(before < middle && middle < after, "\(before.rawValue) \(key) \(after.rawValue)")
    }
}
