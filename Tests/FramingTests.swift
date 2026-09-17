import XCTest
import CoreGraphics
@testable import FaceTrackCore

final class FramingTests: XCTestCase {
    func testCropStaysInsideImageForEdgeFacesAndBothFormats() {
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920)] {
            let bounds = CGRect(origin: .zero, size: size)
            for aspect in [CGFloat(16.0 / 9), CGFloat(9.0 / 16)] {
                for x in [CGFloat(-0.2), 0, 0.5, 0.95, 1.2] {
                    for y in [CGFloat(-0.2), 0, 0.5, 0.95, 1.2] {
                        let crop = Framing.crop(in: bounds, aspect: aspect, face: CGRect(x: x, y: y, width: 0.15, height: 0.2), intensity: 3)
                        XCTAssertGreaterThanOrEqual(crop.minX, 0)
                        XCTAssertGreaterThanOrEqual(crop.minY, 0)
                        XCTAssertLessThanOrEqual(crop.maxX, bounds.maxX + 0.001)
                        XCTAssertLessThanOrEqual(crop.maxY, bounds.maxY + 0.001)
                        XCTAssertEqual(crop.width / crop.height, aspect, accuracy: 0.0001)
                    }
                }
            }
        }
    }
    func testFaceLossReturnsCenteredWideCrop() {
        let crop = Framing.crop(in: CGRect(x: 0, y: 0, width: 1920, height: 1080), aspect: 16.0 / 9, face: nil, intensity: 2)
        XCTAssertEqual(crop, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }
    func testVisionCoordinatesDoNotFlipVertically() {
        let bounds = CGRect(x: 0, y: 0, width: 1080, height: 1920)
        let upper = Framing.crop(in: bounds, aspect: 9.0 / 16, face: CGRect(x: 0.45, y: 0.75, width: 0.1, height: 0.1), intensity: 2)
        let lower = Framing.crop(in: bounds, aspect: 9.0 / 16, face: CGRect(x: 0.45, y: 0.15, width: 0.1, height: 0.1), intensity: 2)
        XCTAssertGreaterThan(upper.midY, lower.midY)
    }
    func testSubjectSelectionStaysWithPreviousFace() {
        let previous = CGRect(x: 0.1, y: 0.3, width: 0.15, height: 0.2)
        let other = CGRect(x: 0.65, y: 0.3, width: 0.3, height: 0.4)
        XCTAssertEqual(Framing.subject(from: [other, previous], previous: previous), previous)
        XCTAssertEqual(Framing.subject(from: [previous, other], previous: nil), other)
    }
    func testInterpolationNeverOvershoots() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 200)
        let b = CGRect(x: 50, y: 50, width: 200, height: 400)
        XCTAssertEqual(Framing.interpolate(a, to: b, amount: 2), b)
        XCTAssertEqual(Framing.interpolate(a, to: b, amount: -1), a)
    }
}

