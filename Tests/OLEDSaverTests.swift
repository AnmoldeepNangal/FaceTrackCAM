import XCTest
@testable import FaceTrackCore

final class OLEDSaverTests: XCTestCase {
    func testCountdownStartsWithStreamAndExpiresAtThirtySeconds() {
        var saver = OLEDSaverState()
        saver.setAuto(true, now: 0)
        XCTAssertNil(saver.deadline)
        saver.setStreaming(true, now: 100)
        saver.advance(to: 129.999)
        XCTAssertFalse(saver.dimmed)
        saver.advance(to: 130)
        XCTAssertTrue(saver.dimmed)
    }

    func testClientUpdatesDoNotDelayCountdownOrRedimAfterWake() {
        var saver = OLEDSaverState()
        saver.setAuto(true, now: 0)
        saver.setStreaming(true, now: 0)
        saver.setStreaming(true, now: 20)
        XCTAssertEqual(saver.deadline, 30)
        saver.advance(to: 30)
        saver.wake()
        saver.setStreaming(true, now: 31)
        saver.advance(to: 500)
        XCTAssertFalse(saver.dimmed)
        XCTAssertNil(saver.deadline)
    }

    func testOffCancelsTimerAndRestoresDimmedState() {
        var saver = OLEDSaverState()
        saver.setStreaming(true, now: 0)
        saver.setAuto(true, now: 10)
        XCTAssertEqual(saver.deadline, 40)
        saver.setAuto(false, now: 20)
        saver.advance(to: 40)
        XCTAssertFalse(saver.dimmed)
        saver.setAuto(true, now: 50)
        saver.advance(to: 80)
        XCTAssertTrue(saver.dimmed)
        saver.setAuto(false, now: 81)
        XCTAssertFalse(saver.dimmed)
    }

    func testStopCancelsAndNewStreamGetsFreshCountdown() {
        var saver = OLEDSaverState()
        saver.setAuto(true, now: 0)
        saver.setStreaming(true, now: 0)
        saver.setStreaming(false, now: 10)
        saver.advance(to: 30)
        XCTAssertFalse(saver.dimmed)
        XCTAssertNil(saver.deadline)
        saver.setStreaming(true, now: 100)
        saver.advance(to: 130)
        XCTAssertTrue(saver.dimmed)
        saver.setStreaming(false, now: 131)
        XCTAssertFalse(saver.dimmed)
    }
}

