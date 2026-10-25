import Testing

@testable import Model

@Suite("Fractional index")
struct FractionalIndexTests {
    @Test(
        "A key has 1 to 64 digits",
        arguments: [(0, false), (1, true), (Limits.maxSortKeyLength, true), (65, false)]
    )
    func length(count: Int, isValid: Bool) {
        let rawValue = String(repeating: "1", count: count)
        if isValid {
            #expect((try? FractionalIndex(rawValue: rawValue))?.rawValue == rawValue)
        } else {
            #expect(throws: ModelError.invalidSortKey(reason: "length \(count)")) {
                try FractionalIndex(rawValue: rawValue)
            }
        }
    }

    @Test("A key with a character outside base 62 is refused", arguments: ["a-b", "é", "A B"])
    func alphabet(rawValue: String) {
        #expect(throws: ModelError.invalidSortKey(reason: "character outside base 62")) {
            try FractionalIndex(rawValue: rawValue)
        }
    }

    @Test("A key that ends with zero is refused")
    func trailingZero() {
        #expect(throws: ModelError.invalidSortKey(reason: "trailing zero")) {
            try FractionalIndex(rawValue: "V0")
        }
    }

    @Test("Keys compare as bytes, so digits come before capitals and capitals before small letters")
    func byteOrder() throws {
        let keys = try ["z", "a", "Z", "A", "9", "1", "a1"].map(FractionalIndex.init(rawValue:))
        #expect(keys.sorted().map(\.rawValue) == ["1", "9", "A", "Z", "a", "a1", "z"])
    }

    @Test("The first key of an empty list is the middle digit")
    func firstKey() throws {
        #expect(try FractionalIndex.between(nil, nil).rawValue == "V")
    }

    @Test(
        "A new key sorts between its neighbors",
        arguments: [
            ("1", "2"), ("1", "3"), ("V", "W"), ("y", "z"), ("z", nil), ("zz", nil), ("01", "1"),
            ("a", "a1"), ("az", "b"), ("Vy", "Vz"), ("1", "11"),
        ] as [(String, String?)]
    )
    func betweenNeighbors(low: String, high: String?) throws {
        let lowKey = try FractionalIndex(rawValue: low)
        let highKey = try high.map(FractionalIndex.init(rawValue:))
        let key = try FractionalIndex.between(lowKey, highKey)
        #expect(lowKey < key)
        #expect(highKey.map { key < $0 } ?? true)
        #expect(try FractionalIndex(rawValue: key.rawValue) == key)
    }

    @Test("A key before the first key sorts before it", arguments: ["1", "01", "V", "001"])
    func beforeFirst(high: String) throws {
        let highKey = try FractionalIndex(rawValue: high)
        let key = try FractionalIndex.between(nil, highKey)
        #expect(key < highKey)
        #expect(try FractionalIndex(rawValue: key.rawValue) == key)
    }

    @Test("Equal keys or keys in the wrong order need a rebalance")
    func wrongOrder() throws {
        let low = try FractionalIndex(rawValue: "a")
        let high = try FractionalIndex(rawValue: "b")
        #expect(throws: ModelError.sortKeyNeedsRebalance) { try FractionalIndex.between(low, low) }
        #expect(throws: ModelError.sortKeyNeedsRebalance) { try FractionalIndex.between(high, low) }
    }

    @Test("A key that needs more than 64 digits needs a rebalance")
    func exhausted() throws {
        let tight = try FractionalIndex(rawValue: String(repeating: "0", count: 63) + "1")
        #expect(throws: ModelError.sortKeyNeedsRebalance) {
            try FractionalIndex.between(nil, tight)
        }
        let full = try FractionalIndex(rawValue: String(repeating: "z", count: 64))
        #expect(throws: ModelError.sortKeyNeedsRebalance) { try FractionalIndex.between(full, nil) }
    }

    @Test("1,000 inserts at random places keep the list in order and the keys unique")
    func randomInserts() throws {
        var random = SeededRandom(state: 11)
        var keys: [FractionalIndex] = []
        for _ in 0..<1_000 {
            let index = keys.isEmpty ? 0 : Int(random.next() % UInt64(keys.count + 1))
            let low = index > 0 ? keys[index - 1] : nil
            let high = index < keys.count ? keys[index] : nil
            keys.insert(try FractionalIndex.between(low, high), at: index)
        }
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        #expect(keys.allSatisfy { $0.rawValue.utf8.count <= Limits.maxSortKeyLength })
    }

    @Test("1,000 inserts at the end and at the start keep the keys in order and short")
    func endGrowth() throws {
        var last = try FractionalIndex.between(nil, nil)
        var first = last
        for _ in 0..<Limits.maxWorkspaces {
            let nextLast = try FractionalIndex.between(last, nil)
            let nextFirst = try FractionalIndex.between(nil, first)
            #expect(last < nextLast)
            #expect(nextFirst < first)
            last = nextLast
            first = nextFirst
        }
        #expect(last.rawValue.utf8.count <= 18)
        #expect(first.rawValue.utf8.count <= 18)
    }

    @Test(
        "A key at an end adds or takes one unit at the fourth digit (D-182)",
        arguments: [
            EndCase(low: "V", expected: "V001"), EndCase(low: "zV", expected: "zV01"),
            EndCase(low: "z", expected: "z001"), EndCase(low: "V00z", expected: "V01"),
            EndCase(low: "zzzz", expected: "zzzz1"), EndCase(low: "V0Z5K", expected: "V0Z5L"),
            EndCase(high: "V", expected: "Uzzz"), EndCase(high: "1z", expected: "1yzz"),
            EndCase(high: "1", expected: "0zzz"), EndCase(high: "01", expected: "00zz"),
            EndCase(high: "0001", expected: "0000z"),
        ]
    )
    func endKeys(endCase: EndCase) throws {
        let lowKey = try endCase.low.map(FractionalIndex.init(rawValue:))
        let highKey = try endCase.high.map(FractionalIndex.init(rawValue:))
        #expect(try FractionalIndex.between(lowKey, highKey).rawValue == endCase.expected)
    }

    struct EndCase: Sendable {
        var low: String?
        var high: String?
        let expected: String
    }
}
