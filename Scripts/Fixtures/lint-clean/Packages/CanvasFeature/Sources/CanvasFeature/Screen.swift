#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import os

    /// Interface code that obeys the rules.
    struct Screen: View {
        @State private var count = 0
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            Text(verbatim: "x").padding(.horizontal)
        }
    }

    /// A UIKit view with the init(coder:) stub.
    public final class CanvasView: UIView {
        private let logger = Logger(subsystem: "pointer", category: "canvas")

        /// Makes the view.
        override public init(frame: CGRect) {
            super.init(frame: frame)
            // TODO(#12): An issue number makes the note legal.
            logger.debug("made")
        }

        // swiftlint:disable:next safe_07_fatal_error
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError("no coder") }
    }
#endif
