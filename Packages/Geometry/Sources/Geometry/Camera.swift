/// The visible part of a canvas: the canvas point at the center of the view and a zoom factor.
///
/// View space has its origin at the top-left corner of the view, in view points. Canvas space is
/// the space of the content, in canvas points.
public struct Camera: Hashable, Codable, Sendable {
    /// The canvas point at the center of the view.
    public var center: Point
    /// View points per canvas point.
    public var zoom: Double

    /// Makes a camera.
    ///
    /// - Precondition: `zoom` is finite and greater than zero, and `center` is finite.
    public init(center: Point, zoom: Double) {
        precondition(
            zoom > 0 && zoom.isFinite,
            "Camera zoom must be positive and finite, got \(zoom)"
        )
        precondition(center.isFinite, "Camera center must be finite, got \(center)")
        self.center = center
        self.zoom = zoom
    }

    /// Returns the canvas point under a view point.
    public func canvasPoint(fromView viewPoint: Point, viewSize: Size) -> Point {
        center + ((viewPoint - Point.zero) - viewSize.halfDiagonal) / zoom
    }

    /// Returns the view point of a canvas point.
    public func viewPoint(fromCanvas canvasPoint: Point, viewSize: Size) -> Point {
        Point.zero + viewSize.halfDiagonal + (canvasPoint - center) * zoom
    }

    /// Returns the transform from view space to canvas space.
    public func viewToCanvas(viewSize: Size) -> Transform {
        let origin = canvasPoint(fromView: .zero, viewSize: viewSize)
        return Transform(scale: 1 / zoom, translation: origin - Point.zero)
    }

    /// Returns the canvas rectangle that the view shows.
    ///
    /// - Precondition: The view size is not negative.
    public func visibleRect(viewSize: Size) -> Rect {
        precondition(
            viewSize.width >= 0 && viewSize.height >= 0,
            "View size \(viewSize) is negative"
        )
        let topLeft = canvasPoint(fromView: .zero, viewSize: viewSize)
        let size = Size(width: viewSize.width / zoom, height: viewSize.height / zoom)
        let rect = Rect(origin: topLeft, size: size)
        assert(
            rect.center.distance(to: center) <= 1e-6 * max(1, size.width),
            "Visible rect is off center"
        )
        return rect
    }

    /// Returns the camera moved so that the content follows a finger that moved by `viewDelta`.
    public func panned(byView viewDelta: Vector) -> Camera {
        Camera(center: center - viewDelta / zoom, zoom: zoom)
    }

    /// Returns the camera with a new zoom. The canvas point under `anchor` stays under it.
    ///
    /// - Precondition: `newZoom` is finite and greater than zero.
    public func zoomed(to newZoom: Double, anchor: Point, viewSize: Size) -> Camera {
        precondition(newZoom > 0 && newZoom.isFinite, "Zoom must be positive, got \(newZoom)")
        let fixed = canvasPoint(fromView: anchor, viewSize: viewSize)
        let offset = (anchor - Point.zero) - viewSize.halfDiagonal
        return Camera(center: fixed - offset / newZoom, zoom: newZoom)
    }

    /// Returns the camera with its zoom clamped to a range.
    ///
    /// - Precondition: The range is above zero.
    public func clamped(to zoomRange: ClosedRange<Double>) -> Camera {
        precondition(zoomRange.lowerBound > 0, "Zoom range \(zoomRange) must be above zero")
        return Camera(
            center: center,
            zoom: min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
        )
    }
}
