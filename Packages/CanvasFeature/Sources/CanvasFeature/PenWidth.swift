/// The widths of the pen in canvas points (TOOL-02, TOOL-09, D-199). The user picks one in the
/// palette while the pen is the selected tool. No other tool has a width.
public enum PenWidth: Double, CaseIterable, Sendable {
    /// A thin line, for details and small labels: 1 canvas point (D-199).
    case thin = 1
    /// The standard line of D-37, the width at each launch: 2 canvas points.
    case standard = 2
    /// A thick line, for headings and boxes: 4 canvas points (D-199).
    case thick = 4

    /// The width in canvas points.
    var canvasPoints: Double { rawValue }
}
