/// The eraser size that the user picked, shared by every canvas of the app while it runs
/// (TOOL-04, D-201). `PointerApp` holds one and gives it to each canvas screen (ARCH-05). A launch
/// starts with the standard size, because the device state does not store the size (D-199).
@MainActor
public final class EraserSettings {
    /// The size of the next erase gesture.
    public var size = EraserSize.standard

    /// Makes the settings with the standard size.
    public init() {}
}
