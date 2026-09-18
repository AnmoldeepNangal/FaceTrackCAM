import XCTest
import Foundation
@testable import FaceTrackCore

final class StreamServerTests: XCTestCase {
    func testRealHTTPRemoteLifecycle() throws {
        let server = StreamServer()
        let started = expectation(description: "listener ready")
        var didStart = false
        server.onStatus = { status in
            XCTAssertNil(status.error)
            if status.running && !didStart { didStart = true; started.fulfill() }
        }
        var remoteApplied = false
        server.onRemoteState = { ["applied": remoteApplied] }
        server.onRemoteCommand = { command in
            guard command["action"] as? String == "wake" else { return "Invalid action" }
            remoteApplied = true; return nil
        }
        server.start(token: "integration-token", remoteToken: "remote-secret")
        wait(for: [started], timeout: 10)
        defer {
            let stopped = expectation(description: "listener stopped")
            server.onStatus = { status in if !status.running { stopped.fulfill() } }
            server.stop()
            wait(for: [stopped], timeout: 10)
        }

        for (path, status) in [("/status?token=integration-token", 200), ("/status?token=wrong", 403),
                               ("/missing?token=integration-token", 404), ("/stream.mjpg?token=integration-token", 404)] {
            let done = expectation(description: path)
            let url = try XCTUnwrap(URL(string: "http://127.0.0.1:8080" + path))
            URLSession.shared.dataTask(with: url) { data, response, error in
                XCTAssertNil(error)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, status)
                XCTAssertFalse(data?.isEmpty ?? true)
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 10)
        }

        for key in ["integration-token", "remote-secret"] {
            let done = expectation(description: "remote command \(key)")
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8080/remote/control?token=\(key)")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{\"action\":\"wake\"}".utf8)
            URLSession.shared.dataTask(with: request) { data, response, error in
                XCTAssertNil(error)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, key == "remote-secret" ? 200 : 403)
                if key == "remote-secret" { XCTAssertTrue(String(decoding: data ?? Data(), as: UTF8.self).contains("true")) }
                done.fulfill()
            }.resume()
            wait(for: [done], timeout: 10)
            XCTAssertEqual(remoteApplied, key == "remote-secret")
        }
    }
}

