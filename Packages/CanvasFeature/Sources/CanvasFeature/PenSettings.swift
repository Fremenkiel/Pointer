/// The pen width that the user picked, shared by every canvas of the app while it runs (TOOL-09,
/// D-199). `PointerApp` holds one and gives it to each canvas screen (ARCH-05). A launch starts
/// with the standard width, because the device state does not store the width (D-199).
@MainActor
public final class PenSettings {
    /// The width of the next stroke.
    public var width = PenWidth.standard

    /// Makes the settings with the standard width.
    public init() {}
}
