import Testing

@testable import CanvasFeature

@Suite("Palm guard")
struct PalmGuardTests {
    @Test("A finger touch with a finger radius moves the camera")
    func finger() {
        #expect(PalmGuard().allowsFingerTouch(at: 10, majorRadius: 10))
    }

    @Test("A touch while the pencil draws is ignored (D-36)")
    func pencilDown() {
        var guardState = PalmGuard()
        guardState.pencilBegan()
        #expect(guardState.isPencilDown)
        #expect(!guardState.allowsFingerTouch(at: 10, majorRadius: 10))
    }

    @Test(
        "A touch shortly after the pencil lifts is ignored",
        arguments: [(10.1, false), (10.149, false), (10.151, true)]
    )
    func cooldown(time: Double, allowed: Bool) {
        var guardState = PalmGuard()
        guardState.pencilBegan()
        guardState.pencilEnded(at: 10)
        #expect(guardState.allowsFingerTouch(at: time, majorRadius: 10) == allowed)
    }

    @Test(
        "A touch with a palm radius is ignored",
        arguments: [(PalmGuard.palmRadius, true), (PalmGuard.palmRadius + 1, false)]
    )
    func palm(radius: Double, allowed: Bool) {
        #expect(PalmGuard().allowsFingerTouch(at: 0, majorRadius: radius) == allowed)
    }

    @Test("More pencil ends than begins do not go below zero")
    func balance() {
        var guardState = PalmGuard()
        guardState.pencilEnded(at: 1)
        guardState.pencilBegan()
        #expect(guardState.isPencilDown)
    }

    @Test(
        "The radius of a UI test takes the synthesized touches of XCTest and refuses a larger one",
        arguments: [(32.67, true), (PalmGuard.uiTestPalmRadius, true), (40.01, false)]
    )
    func uiTestRadius(radius: Double, allowed: Bool) {
        let guardState = PalmGuard(radius: PalmGuard.uiTestPalmRadius)
        #expect(guardState.allowsFingerTouch(at: 0, majorRadius: radius) == allowed)
        #expect(PalmGuard().allowsFingerTouch(at: 0, majorRadius: 32.67) == false)
    }
}
