import Foundation

/// The 1€ filter of Casiez et al., CHI 2012, for one coordinate.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: Double?

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    mutating func filter(_ value: Double, time: Double) -> Double {
        guard let previous = lastValue, let previousTime = lastTime else {
            lastValue = value
            lastTime = time
            return value
        }
        let dt = max(time - previousTime, 1e-4)
        lastTime = time
        let derivative = (value - previous) / dt
        let smoothedDerivative = lastDerivative + Self.alpha(derivativeCutoff, dt) * (derivative - lastDerivative)
        lastDerivative = smoothedDerivative
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let result = previous + Self.alpha(cutoff, dt) * (value - previous)
        lastValue = result
        return result
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// Two 1€ filters, one for x and one for y.
struct PointFilter {
    var x: OneEuroFilter
    var y: OneEuroFilter
    var isEnabled = true

    init(minCutoff: Double, beta: Double, derivativeCutoff: Double) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
    }

    mutating func filter(_ point: CGPoint, time: Double) -> CGPoint {
        guard isEnabled else { return point }
        return CGPoint(x: x.filter(point.x, time: time), y: y.filter(point.y, time: time))
    }
}
