import XCTest
@testable import FaceTrackCore

final class StreamProtocolTests: XCTestCase {
    private func parse(_ request: String) -> HTTPRequestResult { StreamProtocol.parse(Data(request.utf8), token: "secret") }
    func testFragmentedRequestWaitsForHeaderTerminator() {
        XCTAssertEqual(parse("GET /stream.mjpg?token=secret HTTP/1.1\r\nHost: phone\r\n"), .incomplete)
        XCTAssertEqual(parse("GET /stream.mjpg?token=secret HTTP/1.1\r\nHost: phone\r\n\r\n"), .route("/stream.mjpg"))
    }
    func testAllRoutesRequireCurrentToken() {
        for route in ["/stream.mjpg", "/view", "/status"] {
            XCTAssertEqual(parse("GET \(route) HTTP/1.1\r\n\r\n"), .rejected(403))
            XCTAssertEqual(parse("GET \(route)?token=old HTTP/1.1\r\n\r\n"), .rejected(403))
            XCTAssertEqual(parse("GET \(route)?token=secret HTTP/1.1\r\n\r\n"), .route(route))
        }
    }
    func testRejectsDuplicateTokensAndUnknownRoutes() {
        XCTAssertEqual(parse("GET /view?token=wrong&token=secret HTTP/1.1\r\n\r\n"), .rejected(403))
        XCTAssertEqual(parse("GET /missing?token=secret HTTP/1.1\r\n\r\n"), .rejected(404))
    }
    func testRejectsMalformedAndOversizedRequests() {
        XCTAssertEqual(parse("POST /view?token=secret HTTP/1.1\r\n\r\n"), .rejected(405))
        XCTAssertEqual(parse("garbage\r\n\r\n"), .rejected(400))
        XCTAssertEqual(parse("GET //evil/view?token=secret HTTP/1.1\r\n\r\n"), .rejected(400))
        XCTAssertEqual(parse(String(repeating: "x", count: 8193)), .rejected(431))
    }
    func testMultipartContainsExactLengthAndBytes() {
        let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        let expected = Data("--facetrack-frame\r\nContent-Type: image/jpeg\r\nContent-Length: 4\r\n\r\n".utf8) + jpeg + Data("\r\n".utf8)
        XCTAssertEqual(StreamProtocol.frame(jpeg), expected)
    }
    func testHTTPContentLengthCountsUTF8Bytes() {
        let data = StreamProtocol.response(type: "text/plain", body: Data("✓".utf8))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Content-Length: 3\r\n"))
    }
}
