/// A fixture for the exits of a `guard` (D-176) and the bound of 10 code lines (TEST-06).
public enum Exits {
    /// Returns `nil` as an answer, not as an error, so the `guard` does not count.
    public static func answer(_ values: [Int]) -> Int? {
        guard let first = values.first else { return nil }
        let second = values.dropFirst().first ?? 0
        let sum = first + second
        let twice = sum * 2
        let half = twice / 2
        let same = half == sum
        let offset = same ? 0 : 1
        let result = sum + offset
        let check = result - offset
        let unused = check * 0
        return check + unused
    }

    /// Returns `nil` as the error value of its contract, with the marker.
    public static func parsed(_ values: [Int]) -> Int? {
        guard let first = values.first else {
            return nil  // contract: error value
        }
        let second = values.dropFirst().first ?? 0
        let sum = first + second
        let twice = sum * 2
        let half = twice / 2
        let same = half == sum
        let offset = same ? 0 : 1
        let result = sum + offset
        return result
    }

    /// Has exactly 10 code lines and no check, at the bound.
    public static func atBound(_ value: Int) -> Int {
        let a = value + 1
        let b = a + 1
        let c = b + 1
        let d = c + 1
        let e = d + 1
        let f = e + 1
        let g = f + 1
        let h = g + 1
        let i = h + 1
        return i
    }

    /// Has 11 code lines and no check, one past the bound.
    public static func pastBound(_ value: Int) -> Int {
        let a = value + 1
        let b = a + 1
        let c = b + 1
        let d = c + 1
        let e = d + 1
        let f = e + 1
        let g = f + 1
        let h = g + 1
        let i = h + 1
        let j = i + 1
        return j
    }
}
