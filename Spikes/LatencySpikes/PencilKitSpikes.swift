import Metal
import PencilKit
import UIKit

/// Makes a canvas that draws white monoline ink on black at all interface styles.
func makeWhiteInkCanvas(width: Double, opaque: Bool) -> PKCanvasView {
    let canvas = PKCanvasView()
    canvas.overrideUserInterfaceStyle = .dark
    canvas.backgroundColor = opaque ? .black : .clear
    canvas.isOpaque = opaque
    #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
    #else
        canvas.drawingPolicy = .pencilOnly
    #endif
    canvas.minimumZoomScale = 1
    canvas.maximumZoomScale = 1
    canvas.isScrollEnabled = false
    canvas.contentInsetAdjustmentBehavior = .never
    canvas.tool = whiteMonoline(width: width)
    return canvas
}

/// PencilKit adapts ink colors to the interface style. In dark style, this light color shows as white.
func whiteMonoline(width: Double) -> PKInkingTool {
    let color = PKInkingTool.convertColor(.white, from: .dark, to: .light)
    return PKInkingTool(.monoline, color: color, width: width)
}

/// The `PencilKit` spike. Latency is measured with the camera only: PencilKit exposes no presented time.
final class PencilKitSpikeView: UIView {
    let canvas: PKCanvasView

    init(settings: SpikeSettings) {
        canvas = makeWhiteInkCanvas(width: settings.penWidth, opaque: true)
        super.init(frame: .zero)
        backgroundColor = .black
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
    }

    func clear() { canvas.drawing = PKDrawing() }
}

/// The `Hybrid` spike (D-33): PencilKit draws the live stroke at zoom 1. At pencil lift the stroke
/// moves to the Metal renderer, and it leaves the `PKCanvasView` after the Metal frame is on the glass.
final class HybridSpikeView: UIView, PKCanvasViewDelegate {
    let metal = MetalCanvasView(frame: .zero)
    let canvas: PKCanvasView
    var log: LatencyLog { metal.log }
    var onHandoff: (() -> Void)?

    private var isRemoving = false

    init(settings: SpikeSettings) {
        canvas = makeWhiteInkCanvas(width: settings.penWidth * settings.zoom, opaque: false)
        super.init(frame: .zero)
        backgroundColor = .black
        metal.settings = settings
        addSubview(metal)
        addSubview(canvas)
        canvas.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    var settings: SpikeSettings {
        get { metal.settings }
        set {
            metal.settings = newValue
            canvas.tool = whiteMonoline(width: newValue.penWidth * newValue.zoom)
            metal.requestFrame()
        }
    }

    /// The width that PencilKit uses after its own clamp.
    var toolWidth: Double { Double((canvas.tool as? PKInkingTool)?.width ?? 0) }

    override func layoutSubviews() {
        super.layoutSubviews()
        metal.frame = bounds
        canvas.frame = bounds
    }

    func clear() {
        metal.clear()
        isRemoving = true
        canvas.drawing = PKDrawing()
        isRemoving = false
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isRemoving, !canvasView.drawing.strokes.isEmpty else { return }
        let changedTime = CACurrentMediaTime()
        let drawing = canvasView.drawing
        let zoom = settings.zoom
        let radius = settings.penWidth / 2
        let scale = contentScaleFactor
        let size = bounds.size

        var capsules: [Capsule] = []
        var widthSum = 0.0
        var widthCount = 0
        for stroke in drawing.strokes {
            var previous: CGPoint?
            for point in stroke.path.interpolatedPoints(by: .distance(0.5)) {
                let view = point.location.applying(stroke.transform)
                let canvasPoint = CGPoint(x: view.x / zoom, y: view.y / zoom)
                capsules.append(Capsule(previous ?? canvasPoint, canvasPoint, radius: radius))
                previous = canvasPoint
                widthSum += point.size.width
                widthCount += 1
            }
        }
        let start = metal.renderer.committedCount
        metal.renderer.append(capsules)
        let range = start..<metal.renderer.committedCount

        let index = log.addHandoff(HandoffRecord(
            drawingChangedTime: changedTime, zoom: zoom, toolWidth: toolWidth,
            meanPencilKitPointWidth: widthCount > 0 ? widthSum / Double(widthCount) : 0))

        var pencilKitImage = UIImage()
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            pencilKitImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
        }
        metal.renderer.renderOffscreen(range: range, zoom: zoom, viewSize: size, scale: scale) { [weak self] texture in
            guard let self else { return }
            let result = compare(pencilKit: pencilKitImage, metal: texture)
            log.updateHandoff(index) {
                $0.maxDifference = result.maxDifference
                $0.differingPixels = result.differingPixels
                $0.comparedPixels = result.comparedPixels
                $0.inkRatio = result.inkRatio
            }
            onHandoff?()
        }

        metal.onPresented = { [weak self] presentedTime in
            guard let self else { return }
            log.updateHandoff(index) { $0.metalPresentedTime = presentedTime }
            isRemoving = true
            canvas.drawing = PKDrawing()
            isRemoving = false
            onHandoff?()
        }
        metal.requestFrame()
    }
}

/// The result of one pixel comparison at the handoff.
struct HandoffComparison {
    var maxDifference: Int
    var differingPixels: Int
    var comparedPixels: Int
    var inkRatio: Double
}

/// Compares the PencilKit image of the stroke with the Metal rendering of the same stroke,
/// both on black. Only pixels where either image has ink count.
func compare(pencilKit: UIImage, metal: MTLTexture) -> HandoffComparison {
    let width = metal.width
    let height = metal.height
    var metalPixels = [UInt8](repeating: 0, count: width * height * 4)
    metal.getBytes(&metalPixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

    var pencilKitPixels = [UInt8](repeating: 0, count: width * height * 4)
    if let image = pencilKit.cgImage,
        let context = CGContext(
            data: &pencilKitPixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    {
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var maxDifference = 0
    var differing = 0
    var compared = 0
    var metalInk = 0
    var pencilKitInk = 0
    for pixel in 0..<(width * height) {
        // BGRA and RGBA: the green channel sits at offset 1 in both. Ink is gray, so one channel is enough.
        let m = Int(metalPixels[pixel * 4 + 1])
        let p = Int(pencilKitPixels[pixel * 4 + 1])
        guard m > 0 || p > 0 else { continue }
        compared += 1
        metalInk += m
        pencilKitInk += p
        let difference = abs(m - p)
        maxDifference = max(maxDifference, difference)
        if difference > 64 { differing += 1 }
    }
    return HandoffComparison(
        maxDifference: maxDifference, differingPixels: differing, comparedPixels: compared,
        inkRatio: pencilKitInk > 0 ? Double(metalInk) / Double(pencilKitInk) : 0)
}
