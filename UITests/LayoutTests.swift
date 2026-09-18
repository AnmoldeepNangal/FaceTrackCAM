import XCTest

final class LayoutTests: XCTestCase {
    func testPreviewUsesFullDisplayAndControlsStayInsideIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-appMode", "host"]
        app.launch()
        // The simulator has no camera. Dismiss only its permission/error alerts.
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            let alert = app.alerts.firstMatch
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() }
            else if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
        }
        if app.alerts.buttons["OK"].waitForExistence(timeout: 2) { app.alerts.buttons["OK"].tap() }

        let preview = app.otherElements["camera.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let screen = XCUIScreen.main.screenshot().image.size
        let frame = preview.frame
        XCTAssertEqual(frame.width / frame.height, screen.width / screen.height, accuracy: 0.005,
                       "Preview or application window is letterboxed")
        XCTAssertEqual(frame.minX, 0, accuracy: 1)
        XCTAssertEqual(frame.minY, 0, accuracy: 1)
        XCTAssertEqual(frame.width, app.frame.width, accuracy: 1)
        XCTAssertEqual(frame.height, app.frame.height, accuracy: 1)

        let moon = app.buttons["camera.oled"]
        XCTAssertTrue(moon.exists)
        XCTAssertEqual(moon.frame.width, 44, accuracy: 1)
        XCTAssertEqual(moon.frame.height, 44, accuracy: 1)
        XCTAssertGreaterThan(moon.frame.minY, frame.minY)
        XCTAssertLessThan(moon.frame.maxX, frame.maxX)
        XCTAssertTrue(app.buttons["FaceTrack"].isHittable)
        XCTAssertTrue(app.buttons["Settings"].isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Full-screen camera and safe-area controls"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
