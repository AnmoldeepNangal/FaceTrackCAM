import Foundation
import Network
import CoreImage
import ImageIO

final class StreamServer {
    struct Status {
        var running = false
        var clients = 0
        var error: String?
    }
    private final class Client {
        let connection: NWConnection
        var request = Data()
        var streaming = false
        var sending = false
        var lastProgress = Date()
        init(_ connection: NWConnection) { self.connection = connection }
    }

    var onStatus: ((Status) -> Void)?
    private let queue = DispatchQueue(label: "cam.network", qos: .userInitiated)
    private let gate = NSLock()
    private var framePending = false
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var timer: DispatchSourceTimer?
    private var token = ""
    private var running = false
    private var size = CGSize(width: 1280, height: 720)
    private var frames: UInt64 = 0

    func start(token: String) {
        queue.async {
            self.stopInternal()
            self.token = token
            self.frames = 0
            do {
                let listener = try NWListener(using: .tcp, on: 8080)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    guard let self, let listener, self.listener === listener else { return }
                    switch state {
                    case .ready: self.running = true; self.report()
                    case .failed(let error):
                        self.stopInternal(); self.report(error: "Stream could not start: \(error.localizedDescription)")
                    case .waiting(let error): self.report(error: "Network waiting: \(error.localizedDescription)")
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: self.queue)
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(deadline: .now() + 2, repeating: 2)
                timer.setEventHandler { [weak self] in self?.expireClients() }
                timer.resume(); self.timer = timer
            } catch { self.report(error: error.localizedDescription) }
        }
    }

    func stop() { queue.async { self.stopInternal(); self.report() } }

    private func stopInternal() {
        running = false
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        timer?.cancel(); timer = nil
        clients.values.forEach { $0.connection.cancel() }
        clients.removeAll()
    }

    // A single frame may wait for encoding; newer frames are dropped until it completes.
    func offer(_ image: CIImage) {
        gate.lock()
        guard !framePending else { gate.unlock(); return }
        framePending = true
        gate.unlock()
        queue.async {
            defer { self.gate.lock(); self.framePending = false; self.gate.unlock() }
            guard self.running else { return }
            self.size = image.extent.size
            let ready = self.clients.filter { $0.value.streaming && !$0.value.sending }
            guard !ready.isEmpty else { return }
            guard let jpeg = self.context.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.75]) else { return }
            let packet = StreamProtocol.frame(jpeg)
            self.frames += 1
            for (id, client) in ready {
                client.sending = true
                client.connection.send(content: packet, completion: .contentProcessed { [weak self, weak client] error in
                    guard let self, let client, self.clients[id] === client else { return }
                    if error != nil { self.remove(id) }
                    else { client.sending = false; client.lastProgress = Date() }
                })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        guard running, clients.count < 8 else { connection.cancel(); return }
        let id = UUID()
        let client = Client(connection)
        clients[id] = client
        connection.stateUpdateHandler = { [weak self] state in
            switch state { case .failed, .cancelled: self?.remove(id); default: break }
        }
        connection.start(queue: queue)
        read(id)
    }

    private func read(_ id: UUID) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak client] data, _, complete, error in
            guard let self, let client, self.clients[id] === client else { return }
            if error != nil || complete { self.remove(id); return }
            if let data { client.request.append(data) }
            switch StreamProtocol.parse(client.request, token: self.token) {
            case .incomplete: self.read(id)
            case .rejected(let status): self.reply(id, status: status, type: "text/plain", body: Data("Request rejected".utf8))
            case .route(let path): self.route(path, id: id)
            }
        }
    }

    private func route(_ path: String, id: UUID) {
        guard let client = clients[id] else { return }
        client.request.removeAll()
        switch path {
        case "/stream.mjpg":
            guard clients.values.filter({ $0.streaming }).count < 3 else {
                reply(id, status: 503, type: "text/plain", body: Data("Three viewers are already connected.".utf8)); return
            }
            // Reserve the slot before the asynchronous header send completes.
            client.streaming = true
            client.sending = true
            client.connection.send(content: StreamProtocol.streamHeader, completion: .contentProcessed { [weak self, weak client] error in
                guard let self, let client, self.clients[id] === client else { return }
                if error != nil { self.remove(id); return }
                client.streaming = true; client.sending = false; client.lastProgress = Date(); self.report()
                self.watchDisconnect(id)
            })
        case "/view":
            let html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width"><title>FaceTrackCam</title>
            <style>html,body{margin:0;background:#000;width:100%;height:100%;overflow:hidden}img{width:100%;height:100%;object-fit:contain}</style></head>
            <body><img alt="FaceTrackCam live video" src="/stream.mjpg?token=\(token)"></body></html>
            """
            reply(id, type: "text/html; charset=utf-8", body: Data(html.utf8))
        case "/status":
            let data = (try? JSONSerialization.data(withJSONObject: ["streaming": running, "clients": clients.values.filter { $0.streaming }.count,
                "width": Int(size.width), "height": Int(size.height), "encodedFrames": frames, "audio": false])) ?? Data("{}".utf8)
            reply(id, type: "application/json", body: data)
        default: break
        }
    }

    private func watchDisconnect(_ id: UUID) {
        guard let client = clients[id] else { return }
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, _, _ in self?.remove(id) }
    }

    private func reply(_ id: UUID, status: Int = 200, type: String, body: Data) {
        guard let client = clients[id] else { return }
        client.sending = true
        client.connection.send(content: StreamProtocol.response(status: status, type: type, body: body),
                               completion: .contentProcessed { [weak self] _ in self?.remove(id) })
    }

    private func expireClients() {
        let now = Date()
        let expired = clients.filter { _, client in
            now.timeIntervalSince(client.lastProgress) > (client.streaming ? 15 : 5)
        }.map(\.key)
        expired.forEach(remove)
    }

    private func remove(_ id: UUID) {
        guard let client = clients.removeValue(forKey: id) else { return }
        client.connection.stateUpdateHandler = nil
        client.connection.cancel()
        report()
    }

    private func report(error: String? = nil) {
        let status = Status(running: running, clients: clients.values.filter { $0.streaming }.count, error: error)
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }
}

