import XCTest

/// The main flows of code-of-code.md section 3.11 with finger touches, in a new process of the
/// app on a temporary library (D-178). The draw step needs Apple Pencil, so it runs in process
/// in `PointerDeviceTests`. These tests check that a finger never draws (TOOL-03).
@MainActor
final class FlowTests: XCTestCase {
    /// The longest wait for a state of the app, in seconds. A launch on an empty library takes
    /// less than 2 s on the iPad.
    private static let timeout: TimeInterval = 20

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// Starts the app on a new empty library in its temporary folder. `fillStrokes` adds
    /// strokes that are never saved (D-55), so that an export has ink without a pencil.
    private func launch(fillStrokes: Int = 0) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestLibrary", UUID().uuidString]
        if fillStrokes > 0 {
            app.launchArguments += ["-fillStrokes", String(fillStrokes)]
        }
        app.launch()
        waitForCanvas(app)
        return app
    }

    /// Waits until a canvas shows and loads nothing.
    private func waitForCanvas(_ app: XCUIApplication) {
        expect(app, "uiTest.loading", "false")
    }

    /// Waits until the probe element `identifier` shows `value`, and fails after the timeout.
    private func expect(
        _ app: XCUIApplication,
        _ identifier: String,
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let element = app.descendants(matching: .any)[identifier]
        let isShown = element.wait(for: \.stringValue, toEqual: value, timeout: Self.timeout)
        XCTAssertTrue(
            isShown,
            "\(identifier) is \(element.stringValue), not \(value)",
            file: file,
            line: line
        )
    }

    /// The middle of the screen.
    private func center(_ app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    }

    func testCreateWorkspace() {
        let app = launch()
        let selector = app.buttons["workspaces"]
        XCTAssertEqual(selector.stringValue, "Workspace")
        selector.tap()
        app.buttons["newWorkspace"].tap()
        // The system alert drops the identifier of a SwiftUI text field, so the test takes the
        // one field of the alert.
        let title = app.alerts.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout))
        title.typeText("Graphs")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(selector.wait(for: \.stringValue, toEqual: "Graphs", timeout: Self.timeout))
        waitForCanvas(app)
        expect(app, "uiTest.strokes", "0")
        expect(app, "uiTest.level", "0")
    }

    func testFingerPansAndNeverDraws() {
        let app = launch()
        let camera = app.descendants(matching: .any)["uiTest.camera"]
        let before = camera.stringValue
        let start = center(app)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 300, dy: 200)))
        waitForCanvas(app)
        XCTAssertNotEqual(camera.stringValue, before, "The finger pans the camera")
        expect(app, "uiTest.strokes", "0")
        expect(app, "uiTest.cards", "0")
        XCTAssertFalse(app.buttons["undo"].isEnabled)
    }

    func testOpenLeaveAndUndoCard() {
        let app = launch()
        app.buttons["newCard"].tap()
        // The new card shows centered on the left edge with a width of 320 points (D-117,
        // D-118), so its visible half lies within 160 points of the edge.
        let window = app.windows.firstMatch.frame
        let edge = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 80, dy: window.height / 2))
        edge.press(
            forDuration: 0.05,
            thenDragTo: edge.withOffset(CGVector(dx: 500, dy: 0)),
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )
        expect(app, "uiTest.cards", "1")
        edge.withOffset(CGVector(dx: 500, dy: 0)).tap()
        expect(app, "uiTest.level", "1")
        waitForCanvas(app)
        app.buttons["up"].tap()
        expect(app, "uiTest.level", "0")
        waitForCanvas(app)
        expect(app, "uiTest.cards", "1")
        app.buttons["undo"].tap()
        expect(app, "uiTest.cards", "0")
        app.buttons["redo"].tap()
        expect(app, "uiTest.cards", "1")
    }

    func testExportOpensShareSheet() {
        let app = launch(fillStrokes: 100)
        expect(app, "uiTest.strokes", "100")
        app.buttons["export"].tap()
        // The share sheet of UIKit has this identifier.
        let sheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Self.timeout))
        app.otherElements["PopoverDismissRegion"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["export"].isEnabled)
    }

    func testExportOfEmptyCanvasShowsMessage() {
        let app = launch()
        app.buttons["export"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: Self.timeout))
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: Self.timeout))
    }
}

extension XCUIElement {
    /// The accessibility value as text, or an empty string. `wait(for:toEqual:timeout:)` needs
    /// an equatable value, and `value` is `Any?`.
    var stringValue: String { value as? String ?? "" }
}
