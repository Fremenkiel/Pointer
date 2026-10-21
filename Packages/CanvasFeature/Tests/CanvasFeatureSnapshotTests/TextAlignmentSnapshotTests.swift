import Geometry
import Model
import Rendering
import Testing
import UIKit

@testable import CanvasFeature

/// M5 acceptance 2: text on the canvas and text in edit mode line up to within one pixel at zoom
/// 0.5, 1, and 4 (D-77, D-85, D-91).
@MainActor
@Suite("Text alignment snapshots")
struct TextAlignmentSnapshotTests {
    /// The display scale of the images.
    private static let scale = 2.0
    /// The space around the box in the images, in view points.
    private static let margin = 8.0

    /// Three lines, one of them past the largest width, so that it wraps at a space (D-83).
    static let wrapped =
        "struct Node {\n  next: Node?\n"
        + "  let values: [Int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377]"
    /// Characters that SF Mono lacks come from fallback fonts (D-84).
    static let fallback = "a → b ü 漢字"

    static func box(_ text: String) throws -> TextBox {
        try TextBox(
            id: TextBoxID(rawValue: UUID()),
            meta: RecordMeta(
                created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
            ),
            canvasID: Fixtures.canvas,
            origin: Point(x: 0, y: 0),
            text: text,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    @Test("The canvas and the edit view line up", arguments: [0.5, 1.0, 4.0])
    func wrappedText(zoom: Double) throws {
        try check(text: Self.wrapped, zoom: zoom, name: "text-align-zoom\(zoom)")
    }

    @Test("Fallback glyphs line up too (D-84)", arguments: [1.0])
    func fallbackText(zoom: Double) throws {
        try check(text: Self.fallback, zoom: zoom, name: "text-align-fallback-zoom\(zoom)")
    }

    /// The two images of one case and the layout of its text.
    private struct Images {
        let canvas: RenderedImage
        let edit: RenderedImage
        let layout: TextLayout
    }

    /// Renders the canvas image and the edit view image of a box at the margin.
    private func images(text: String, zoom: Double) throws -> Images {
        let box = try Self.box(text)
        let layout = TextLayout(text: text)
        // Whole view points, so that both images have the same pixel size.
        let viewSize = Size(
            width: ((layout.size.width + 2 * Self.margin) * zoom).rounded(.up),
            height: ((layout.size.height + 2 * Self.margin) * zoom).rounded(.up)
        )
        // The camera center puts the box origin at the margin.
        let camera = Camera(
            center: Point(
                x: viewSize.width / 2 / zoom - Self.margin,
                y: viewSize.height / 2 / zoom - Self.margin
            ),
            zoom: zoom
        )
        let canvas = try CanvasRenderer().renderImage(
            of: [],
            textBoxes: [box],
            camera: camera,
            viewSize: viewSize,
            displayScale: Self.scale
        )
        let edit = try EditViewImage.render(
            text: text,
            origin: box.origin,
            camera: camera,
            viewSize: viewSize,
            scale: Self.scale
        )
        return Images(canvas: canvas, edit: edit, layout: layout)
    }

    private func check(text: String, zoom: Double, name: String) throws {
        let images = try images(text: text, zoom: zoom)
        let pixels = zoom * Self.scale
        let bands = (0..<images.layout.lineCount).map { line in
            let top = (Self.margin + Double(line) * TextLayout.lineHeight) * pixels
            let bottom = (Self.margin + Double(line + 1) * TextLayout.lineHeight) * pixels
            return Int(top.rounded())...(Int(bottom.rounded()) - 1)
        }
        try #require(images.canvas.width == images.edit.width, "The images differ in width")
        try #require(images.canvas.height == images.edit.height, "The images differ in height")
        let results = TextAlignment.compare(images.canvas, images.edit, bands: bands)
        #expect(results.count == images.layout.lineCount, "Each line shows in both images")
        for result in results {
            #expect(result.passes, "\(name) \(result)")
        }
        let report = results.map { "\(name) \($0)" }.joined(separator: "\n")
        Attachment.record(report, named: "\(name).txt")
        Snapshot.assertMatches(images.canvas, named: "\(name)-canvas")
        Snapshot.assertMatches(
            images.edit,
            named: "\(name)-edit",
            channelTolerance: Snapshot.textChannelTolerance
        )
    }
}

/// Draws the edit view of a text box in the window of the test host, without the caret.
@MainActor
enum EditViewImage {
    static func render(
        text: String,
        origin: Point,
        camera: Camera,
        viewSize: Size,
        scale: Double
    ) throws -> RenderedImage {
        let host = try OnScreenCanvas.host()
        let container = UIView(
            frame: CGRect(x: 0, y: 0, width: viewSize.width, height: viewSize.height)
        )
        container.backgroundColor = .black
        let view = TextEditView()
        view.setText(text)
        container.addSubview(view)
        host.view.addSubview(container)
        defer { container.removeFromSuperview() }
        view.layOut(origin: origin, camera: camera, viewSize: viewSize)
        container.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: container.bounds, format: format).image { _ in
            container.drawHierarchy(in: container.bounds, afterScreenUpdates: true)
        }
        return try pixels(of: image)
    }

    /// The BGRA pixels of an image, top row first, as `RenderedImage` holds them.
    private static func pixels(of image: UIImage) throws -> RenderedImage {
        let cgImage = try #require(image.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        )
        let rect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.draw(cgImage, in: rect)
        let data = try #require(context.makeImage()?.dataProvider?.data as Data?)
        return RenderedImage(width: cgImage.width, height: cgImage.height, pixels: Array(data))
    }
}
