/// A fixture with 4 levels of control flow, one past FLOW-04 (D-175).
enum Deep {
    static func deep(_ values: [Int]) -> Int {
        var total = 0
        for value in values {
            if value > 0 {
                values.forEach { other in
                    if other > value { total += 1 }
                }
            }
        }
        return total
    }
}
