/// A fixture at 3 levels: an `else if` chain stays flat, a `case` adds no level of its own, a
/// `catch` sits at the level of its `do`, and a nested function starts at 0 (D-175).
enum Flat {
    static func flat(_ values: [Int]) -> Int {
        var total = 0
        for value in values {
            if value > 2 {
                total += 3
            } else if value > 1 {
                total += 2
            } else if value > 0 {
                switch value {
                case 1: total += 1
                default: break
                }
            }
        }
        do {
            try check(total)
        } catch {
            for value in values { if value > 0 { total = 0 } }
        }
        func inner() -> Int {
            for value in values { if value > 0 { values.forEach { total += $0 } } }
            return total
        }
        return inner()
    }

    static func check(_ value: Int) throws {}
}
