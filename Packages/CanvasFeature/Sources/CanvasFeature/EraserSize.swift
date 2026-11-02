/// The sizes of the eraser as a radius in view points (TOOL-04, D-128, D-201). The user picks one
/// in the palette while the eraser is the selected tool. The size stays the same on the screen at
/// every zoom.
public enum EraserSize: Double, CaseIterable, Sendable {
    /// A small eraser, for a single line in dense ink: 4 view points (D-201).
    case small = 4
    /// The standard eraser of D-128, the size at each launch: 8 view points.
    case standard = 8
    /// A large eraser, for a whole word or a sketch: 16 view points (D-201).
    case large = 16

    /// The radius in view points.
    var viewPoints: Double { rawValue }
}
