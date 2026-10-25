/// A sort key that puts an item between two others without a change to any other item.
///
/// The key is a string of base-62 digits ("0" to "9", "A" to "Z", "a" to "z"). The digits are in
/// ASCII order, so keys compare as bytes (data-model.md section 6). A key is never empty, has at
/// most `Limits.maxSortKeyLength` digits, and never ends with "0". Without a trailing "0", a key
/// always fits between two different keys. The midpoint follows David Greenspan, "Implementing
/// Fractional Indexing", 2020. At the ends of the list, a new key adds or takes one unit at the
/// digit `stepWidth`, or at the last digit of a longer key (D-182). Appends at one end thus keep
/// keys of 4 digits for about seven million keys.
public struct FractionalIndex: Hashable, Comparable, Sendable {
    /// The digits of the key.
    public let rawValue: String

    /// The digit at which a key at an end of the list adds or takes one unit (D-182). The keys
    /// of 1,000,000 appends are at most 4 digits long. Before, a list that grew at one end
    /// reached `Limits.maxSortKeyLength` after 3,874 keys.
    static let stepWidth = 4

    /// The digits in ascending order.
    private static let alphabet = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8
    )

    /// Makes a key from its digits.
    ///
    /// - Throws: `ModelError.invalidSortKey` if the key is empty, is longer than
    ///   `Limits.maxSortKeyLength`, has a character that is not a base-62 digit, or ends with "0".
    public init(rawValue: String) throws(ModelError) {
        // The view needs no copy of the bytes, which a load of 10,000 nodes made 10,000 times.
        let bytes = rawValue.utf8
        guard !bytes.isEmpty, bytes.count <= Limits.maxSortKeyLength else {
            throw .invalidSortKey(reason: "length \(bytes.count)")
        }
        guard bytes.allSatisfy({ Self.digit(of: $0) != nil }) else {
            throw .invalidSortKey(reason: "character outside base 62")
        }
        guard bytes.last != Self.alphabet[0] else {
            throw .invalidSortKey(reason: "trailing zero")
        }
        self.rawValue = rawValue
    }

    private init(digits: [Int]) {
        assert(!digits.isEmpty && digits.last != 0, "A key needs digits without a trailing zero")
        rawValue = String(
            String.UnicodeScalarView(digits.map { Unicode.Scalar(Self.alphabet[$0]) })
        )
    }

    /// Orders keys by their bytes.
    public static func < (left: FractionalIndex, right: FractionalIndex) -> Bool {
        left.rawValue.utf8.lexicographicallyPrecedes(right.rawValue.utf8)
    }

    /// Returns a key that sorts after `low` and before `high`.
    ///
    /// - Parameters:
    ///   - low: The key before the new key, or `nil` for the start of the list.
    ///   - high: The key after the new key, or `nil` for the end of the list.
    /// - Throws: `ModelError.sortKeyNeedsRebalance` if `low` is not less than `high`, or if the
    ///   new key needs more than `Limits.maxSortKeyLength` digits.
    /// - Returns: A valid key that is greater than `low` and less than `high`.
    public static func between(
        _ low: FractionalIndex?,
        _ high: FractionalIndex?
    ) throws(ModelError) -> FractionalIndex {
        let digits: [Int]
        switch (low, high) {
        case (let low?, nil): digits = after(Self.digits(of: low))
        case (nil, let high?): digits = before(Self.digits(of: high))
        case (let low?, let high?):
            guard low < high else { throw .sortKeyNeedsRebalance }
            digits = midpoint(low: Self.digits(of: low), high: Self.digits(of: high))
        case (nil, nil): digits = midpoint(low: [], high: nil)
        }
        guard digits.count <= Limits.maxSortKeyLength else { throw .sortKeyNeedsRebalance }
        let key = FractionalIndex(digits: digits)
        assert(low.map { $0 < key } ?? true, "Key \(key.rawValue) is not after the low key")
        assert(high.map { key < $0 } ?? true, "Key \(key.rawValue) is not before the high key")
        return key
    }

    /// Returns the digits of a key after `low`: `low` plus one unit at its last digit, with at
    /// least `stepWidth` digits, or `low` plus the digit 1 if all digits are the largest.
    private static func after(_ low: [Int]) -> [Int] {
        let largest = alphabet.count - 1
        var digits = low + Array(repeating: 0, count: max(0, stepWidth - low.count))
        // The carry walks at most once over the digits.
        for index in digits.indices.reversed() {
            guard digits[index] == largest else {
                digits[index] += 1
                return withoutTrailingZeros(digits)
            }
            digits[index] = 0
        }
        return low + [1]
    }

    /// Returns the digits of a key before `high`: `high` less one unit at its last digit, with
    /// at least `stepWidth` digits. If that leaves no digit above zero, `high` with its last
    /// digit 1 replaced by 0 and the largest digit.
    private static func before(_ high: [Int]) -> [Int] {
        assert(high.last != 0, "Key \(high) ends with zero")
        let largest = alphabet.count - 1
        var digits = high + Array(repeating: 0, count: max(0, stepWidth - high.count))
        // The borrow walks at most once over the digits.
        for index in digits.indices.reversed() {
            guard digits[index] == 0 else {
                digits[index] -= 1
                let result = withoutTrailingZeros(digits)
                return result.isEmpty ? high.dropLast() + [0, largest] : result
            }
            digits[index] = largest
        }
        return high.dropLast() + [0, largest]
    }

    /// Returns `digits` without the zeros at its end, which add nothing to a fraction.
    private static func withoutTrailingZeros(_ digits: [Int]) -> [Int] {
        guard let last = digits.lastIndex(where: { $0 != 0 }) else { return [] }
        return Array(digits[...last])
    }

    /// Returns the digits between `low` and `high`, where a missing low digit counts as zero and
    /// a missing `high` counts as the end.
    ///
    /// Each pass of the loop appends at least one digit or returns. The result has at most one
    /// digit more than the longer key, so `Limits.maxSortKeyLength + 2` passes are enough.
    private static func midpoint(low: [Int], high: [Int]?) -> [Int] {
        var result: [Int] = []
        var low = low[...]
        var high = high?[...]
        for _ in 0..<(Limits.maxSortKeyLength + 2) {
            if let upper = high {
                let shared = sharedPrefixLength(low, upper)
                result.append(contentsOf: upper.prefix(shared))
                low = low.dropFirst(shared)
                high = upper.dropFirst(shared)
            }
            let lowDigit = low.first ?? 0
            let highDigit = high?.first ?? alphabet.count
            if highDigit - lowDigit > 1 {
                result.append((lowDigit + highDigit + 1) / 2)
                return result
            }
            if let upper = high, upper.count > 1 {
                result.append(highDigit)
                return result
            }
            result.append(lowDigit)
            low = low.dropFirst()
            high = nil
        }
        preconditionFailure(
            "Sort key midpoint did not end within \(Limits.maxSortKeyLength) digits"
        )
    }

    /// Returns the number of leading digits of `high` that equal the digits of `low`, where a
    /// missing low digit counts as zero.
    private static func sharedPrefixLength(_ low: ArraySlice<Int>, _ high: ArraySlice<Int>) -> Int {
        var lowDigits = low.makeIterator()
        var count = 0
        for digit in high {
            guard (lowDigits.next() ?? 0) == digit else { break }
            count += 1
        }
        return count
    }

    private static func digits(of key: FractionalIndex) -> [Int] {
        key.rawValue.utf8.compactMap(digit(of:))
    }

    private static func digit(of byte: UInt8) -> Int? {
        alphabet.firstIndex(of: byte)
    }
}
