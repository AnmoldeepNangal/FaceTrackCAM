import Foundation
import Network
import CoreImage
import CoreMedia

/// Single-port RTSP with RTP interleaved over TCP, so the same socket can cross usbmux.
final class H264RTSPServer {
    private final class Client {
        let connection: NWConnection
        var input = Data()
        var playing = false
        var awaitingKeyframe = true
        var sending = false
        var sequence = UInt16.random(in: 0...UInt16.max)
        var lastProgress = Date()
        let sessionID = UUID().uuidString
        init(_ connection: NWConnection) { self.connection = connection }
    }

    var onError: ((String) -> Void)?
    var onViewers: ((Int) -> Void)?
    private let queue = DispatchQueue(label: "facepull.rtsp", qos: .userInitiated)
    private let encoder = H264Encoder()
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var timer: DispatchSourceTimer?
    private var token = ""
    private var running = false
    private let ssrc = UInt32.random(in: 1...UInt32.max)

    init() {
        encoder.onFrame = { [weak self] frame in
            self?.queue.async { self?.send(frame) }
        }
        encoder.onError = { [weak self] message in self?.report(message) }
    }

    func start(token: String, size: CGSize, frameRate: Double) {
        queue.async {
            self.stopInternal()
            self.token = token
            self.encoder.start(size: size, frameRate: frameRate)
            do {
                let listener = try NWListener(using: .tcp, on: 8554)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.running = true
                    case .failed(let error): self.report("RTSP server stopped: \(error.localizedDescription)"); self.stopInternal()
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 5, repeating: 5)
                timer.setEventHandler { [weak self] in self?.expireClients() }
                timer.resume(); self.timer = timer
            } catch { self.report("RTSP server could not start: \(error.localizedDescription)") }
        }
    }

    func stop() { queue.async { self.stopInternal() } }

    func offer(_ image: CIImage, time: CMTime) {
        // The encoder has a two-frame ceiling; a slow network never stalls capture.
        encoder.offer(image, time: time)
    }

    private func stopInternal() {
        running = false
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        timer?.cancel(); timer = nil
        for client in clients.values { client.connection.cancel() }
        clients.removeAll()
        reportViewers()
        encoder.stop()
    }

    private func accept(_ connection: NWConnection) {
        guard running, clients.count < 8 else { connection.cancel(); return }
        let id = UUID(), client = Client(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.remove(id) }
            if case .cancelled = state { self?.remove(id) }
        }
        connection.start(queue: queue)
        read(id)
    }

    private func read(_ id: UUID) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self, self.clients[id] === client else { return }
            if error != nil || complete { self.remove(id); return }
            if let data { client.input.append(data) }
            guard client.input.count < 16_384 else { self.remove(id); return }
            self.parseRequests(id)
            self.read(id)
        }
    }

    private func parseRequests(_ id: UUID) {
        guard let client = clients[id] else { return }
        let end = Data("\r\n\r\n".utf8)
        while let range = client.input.range(of: end) {
            let header = Data(client.input[..<range.upperBound])
            client.input.removeSubrange(..<range.upperBound)
            guard let request = String(data: header, encoding: .utf8) else { remove(id); return }
            respond(request, id: id)
        }
    }

    private func respond(_ request: String, id: UUID) {
        guard let client = clients[id] else { return }
        let lines = request.components(separatedBy: "\r\n")
        let fields = lines.first?.split(separator: " ") ?? []
        guard fields.count >= 3, fields[2].hasPrefix("RTSP/") else { remove(id); return }
        let method = String(fields[0]).uppercased()
        let uri = String(fields[1])
        let cseq = lines.first(where: { $0.lowercased().hasPrefix("cseq:") })?
            .split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? "0"
        if method == "OPTIONS" {
            reply(id, cseq: cseq, extra: "Public: OPTIONS, DESCRIBE, SETUP, PLAY, GET_PARAMETER, TEARDOWN\r\n")
            return
        }
        guard let url = URLComponents(string: uri), url.path == "/facepull" || url.path == "/facepull/trackID=0",
              url.queryItems?.first(where: { $0.name == "token" })?.value == token else {
            reply(id, cseq: cseq, status: "403 Forbidden"); return
        }
        switch method {
        case "DESCRIBE":
            let control = uri.replacingOccurrences(of: "?token=", with: "/trackID=0?token=")
            let sdp = "v=0\r\no=FacePull 0 0 IN IP4 127.0.0.1\r\ns=FacePull\r\nt=0 0\r\na=control:*\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\na=fmtp:96 packetization-mode=1\r\na=control:\(control)\r\n"
            reply(id, cseq: cseq, extra: "Content-Base: \(uri)\r\nContent-Type: application/sdp\r\n", body: sdp)
        case "SETUP":
            let transport = lines.first(where: { $0.lowercased().hasPrefix("transport:") })?.lowercased() ?? ""
            guard transport.contains("rtp/avp/tcp") && transport.contains("interleaved=") else {
                reply(id, cseq: cseq, status: "461 Unsupported Transport"); return
            }
            reply(id, cseq: cseq, extra: "Transport: RTP/AVP/TCP;unicast;interleaved=0-1;ssrc=\(String(ssrc, radix: 16))\r\nSession: \(client.sessionID);timeout=60\r\n")
        case "PLAY":
            client.playing = true; client.awaitingKeyframe = true
            reportViewers()
            reply(id, cseq: cseq, extra: "Session: \(client.sessionID)\r\nRTP-Info: url=\(uri)/trackID=0;seq=\(client.sequence)\r\n")
        case "GET_PARAMETER": reply(id, cseq: cseq, extra: "Session: \(client.sessionID)\r\n")
        case "TEARDOWN":
            reply(id, cseq: cseq, extra: "Session: \(client.sessionID)\r\n")
            client.playing = false
            reportViewers()
        default: reply(id, cseq: cseq, status: "405 Method Not Allowed")
        }
    }

    private func reply(_ id: UUID, cseq: String, status: String = "200 OK", extra: String = "", body: String = "") {
        guard let client = clients[id] else { return }
        let data = Data("RTSP/1.0 \(status)\r\nCSeq: \(cseq)\r\nServer: FacePull\r\n\(extra)Content-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)
        client.connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.remove(id) }
        })
    }

    private func send(_ frame: H264Encoder.Frame) {
        guard running else { return }
        for (id, client) in clients where client.playing {
            if client.sending { client.awaitingKeyframe = true; continue }
            if client.awaitingKeyframe && !frame.isKeyframe { continue }
            client.awaitingKeyframe = false
            var packet = Data()
            for (index, unit) in frame.nalUnits.enumerated() {
                packet.append(RTPH264.packetize(unit, sequence: &client.sequence, timestamp: frame.timestamp,
                    ssrc: ssrc, marker: index == frame.nalUnits.count - 1))
            }
            client.sending = true
            client.connection.send(content: packet, completion: .contentProcessed { [weak self, weak client] error in
                guard let self, let client, self.clients[id] === client else { return }
                if error != nil { self.remove(id) }
                else { client.sending = false; client.lastProgress = Date() }
            })
        }
    }

    private func remove(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.connection.stateUpdateHandler = nil
        client.connection.cancel()
        reportViewers()
    }

    private func expireClients() {
        let expired = clients.filter { Date().timeIntervalSince($0.value.lastProgress) > 20 }.map(\.key)
        expired.forEach(remove)
    }

    private func reportViewers() {
        let count = clients.values.filter(\.playing).count
        DispatchQueue.main.async { [weak self] in self?.onViewers?(count) }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}

private enum RTPH264 {
    static func packetize(_ unit: Data, sequence: inout UInt16, timestamp: UInt32,
                          ssrc: UInt32, marker: Bool) -> Data {
        guard let first = unit.first else { return Data() }
        let bytes = [UInt8](unit)
        let payloadSize = 1200
        var output = Data()
        if bytes.count <= payloadSize {
            output.append(packet(Data(bytes), sequence: &sequence, timestamp: timestamp, ssrc: ssrc, marker: marker))
        } else {
            let indicator = (first & 0xe0) | 28
            let kind = first & 0x1f
            var offset = 1
            while offset < bytes.count {
                let count = min(payloadSize - 2, bytes.count - offset)
                let start = offset == 1, end = offset + count == bytes.count
                var fragment = Data([indicator, kind | (start ? 0x80 : 0) | (end ? 0x40 : 0)])
                fragment.append(contentsOf: bytes[offset..<(offset + count)])
                output.append(packet(fragment, sequence: &sequence, timestamp: timestamp, ssrc: ssrc, marker: marker && end))
                offset += count
            }
        }
        return output
    }

    private static func packet(_ payload: Data, sequence: inout UInt16, timestamp: UInt32,
                               ssrc: UInt32, marker: Bool) -> Data {
        let length = payload.count + 12
        var result = Data([0x24, 0, UInt8(length >> 8), UInt8(length & 0xff),
                           0x80, marker ? 0xe0 : 0x60,
                           UInt8(sequence >> 8), UInt8(sequence & 0xff),
                           UInt8(timestamp >> 24), UInt8((timestamp >> 16) & 0xff),
                           UInt8((timestamp >> 8) & 0xff), UInt8(timestamp & 0xff),
                           UInt8(ssrc >> 24), UInt8((ssrc >> 16) & 0xff),
                           UInt8((ssrc >> 8) & 0xff), UInt8(ssrc & 0xff)])
        result.append(payload)
        sequence &+= 1
        return result
    }
}

