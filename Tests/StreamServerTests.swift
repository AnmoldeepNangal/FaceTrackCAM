import XCTest
import Foundation
import Network
import CoreImage
@testable import FaceTrackCore

final class StreamServerTests: XCTestCase {
    func testRealHTTPAndJPEGStreamLifecycle() throws {
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
                               ("/missing?token=integration-token", 404), ("/view?token=integration-token", 200)] {
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

        let gotFrame = expectation(description: "received multipart JPEG")
        let disconnected = expectation(description: "viewer removed")
        var sawViewer = false
        server.onStatus = { status in
            if status.clients == 1 {
                sawViewer = true
                server.offer(CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720)))
            } else if sawViewer && status.clients == 0 { disconnected.fulfill() }
        }
        let client = NWConnection(host: "127.0.0.1", port: 8080, using: .tcp)
        let queue = DispatchQueue(label: "test.client")
        var received = Data()
        func receive() {
            client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                XCTAssertNil(error)
                if let data { received.append(data) }
                if received.range(of: Data([0xff, 0xd9])) != nil {
                    XCTAssertNotNil(received.range(of: Data("--facetrack-frame\r\nContent-Type: image/jpeg".utf8)))
                    XCTAssertNotNil(received.range(of: Data([0xff, 0xd8])))
                    gotFrame.fulfill(); client.cancel()
                } else if !complete { receive() }
                else { XCTFail("Stream closed before a JPEG arrived"); gotFrame.fulfill() }
            }
        }
        client.stateUpdateHandler = { state in
            if case .ready = state {
                client.send(content: Data("GET /stream.mjpg?token=integration-token HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8), completion: .contentProcessed { error in XCTAssertNil(error) })
                receive()
            }
        }
        client.start(queue: queue)
        wait(for: [gotFrame, disconnected], timeout: 15)
        client.cancel()
    }
}

