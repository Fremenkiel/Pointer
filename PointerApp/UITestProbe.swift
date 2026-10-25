import CanvasFeature
import UIKit

/// The accessibility elements that the UI tests read (D-178). The app shows them only with the
/// launch argument `-uiTestLibrary`, so VoiceOver never reads them in normal use.
///
/// Each element has a fixed identifier and gives one value of the shown canvas at each read:
/// `uiTest.loading` (`true` or `false`), `uiTest.strokes`, `uiTest.cards`, `uiTest.level`, and
/// `uiTest.camera` (the camera center as "x,y" in whole canvas points).
/// Without a canvas, each value is `none`.
final class UITestProbe: UIView {
    /// One value of the probe, read when the UI test asks for it.
    private final class Element: UIAccessibilityElement {
        private let read: @MainActor () -> String?

        init(container: UIView, identifier: String, read: @escaping @MainActor () -> String?) {
            self.read = read
            super.init(accessibilityContainer: container)
            accessibilityIdentifier = identifier
            accessibilityLabel = identifier
            accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        override var accessibilityValue: String? {
            get { read() ?? "none" }
            // The value comes from the canvas at each read, so a set has no effect.
            set {}
        }
    }

    /// Makes the probe of the canvas that `canvas` gives at each read.
    init(canvas: @escaping @MainActor () -> CanvasViewController?) {
        super.init(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        isUserInteractionEnabled = false
        backgroundColor = .clear
        let values: [(String, @MainActor (CanvasProbe) -> String)] = [
            ("uiTest.loading", { String($0.isLoading) }),
            ("uiTest.strokes", { String($0.strokeCount) }),
            ("uiTest.cards", { String($0.cardCount) }),
            ("uiTest.level", { String($0.level) }),
            ("uiTest.camera", { $0.cameraCenter }),
        ]
        accessibilityElements = values.map { identifier, value in
            Element(container: self, identifier: identifier) { canvas().map { value($0.probe) } }
        }
        assert(accessibilityElements?.count == values.count, "One element per value")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // swiftlint:disable:next safe_07_fatal_error
        fatalError("UITestProbe has no coder support")
    }
}
