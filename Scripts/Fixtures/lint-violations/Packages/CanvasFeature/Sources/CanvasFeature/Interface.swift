// A file header comment.
import Metal
import SQLite3
import SwiftUI
import UIKit

/// Views and calls that the interface rules ban.
struct Interface: View {
    @State var count = 0

    var body: some View {
        Text(verbatim: "x").padding(8)
    }

    func ban() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        _ = UIGraphicsPDFRenderer(bounds: .zero)
        _ = MTLCreateSystemDefaultDevice()
    }
}
