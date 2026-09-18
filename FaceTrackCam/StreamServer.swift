import Foundation
import Network

final class StreamServer {
    struct Status {
        var running = false
        var error: String?
    }
    private final class Client {
        let connection: NWConnection
        var request = Data()
        var lastProgress = Date()
        init(_ connection: NWConnection) { self.connection = connection }
    }

    var onStatus: ((Status) -> Void)?
    var onRemoteState: (() -> [String: Any])?
    var onRemoteCommand: (([String: Any]) -> String?)?
    private let queue = DispatchQueue(label: "cam.network", qos: .userInitiated)
    private var listener: NWListener?
    private var clients: [UUID: Client] = [:]
    private var timer: DispatchSourceTimer?
    private var token = ""
    private var remoteToken: String?
    private var running = false

    func start(token: String, remoteToken: String? = nil) {
        queue.async {
            self.stopInternal()
            self.token = token
            self.remoteToken = remoteToken
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
            switch StreamProtocol.parse(client.request, token: self.token, remoteToken: self.remoteToken) {
            case .incomplete: self.read(id)
            case .rejected(let status): self.reply(id, status: status, type: "text/plain", body: Data("Request rejected".utf8))
            case .route(let path): self.route(path, id: id)
            }
        }
    }

    private func route(_ path: String, id: UUID) {
        guard let client = clients[id] else { return }
        let request = client.request
        client.request.removeAll()
        switch path {
        case "/remote":
            reply(id, type: "text/html; charset=utf-8", body: Data(RemotePage.html.utf8))
        case "/remote/state", "/remote/control":
            let body = request.range(of: Data("\r\n\r\n".utf8)).map { Data(request[$0.upperBound...]) } ?? Data()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var commandError: String?
                if path == "/remote/control" {
                    if let command = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
                        commandError = self.onRemoteCommand?(command) ?? (self.onRemoteCommand == nil ? "Remote control unavailable" : nil)
                    } else { commandError = "Invalid command" }
                }
                var state = self.onRemoteState?() ?? [:]
                if let commandError { state["error"] = commandError }
                let data = (try? JSONSerialization.data(withJSONObject: state)) ?? Data("{}".utf8)
                self.queue.async { self.reply(id, status: commandError == nil ? 200 : 400, type: "application/json", body: data) }
            }
        case "/status":
            let data = (try? JSONSerialization.data(withJSONObject: ["remoteAvailable": running])) ?? Data("{}".utf8)
            reply(id, type: "application/json", body: data)
        default: break
        }
    }

    private func reply(_ id: UUID, status: Int = 200, type: String, body: Data) {
        guard let client = clients[id] else { return }
        client.connection.send(content: StreamProtocol.response(status: status, type: type, body: body),
                               completion: .contentProcessed { [weak self] _ in self?.remove(id) })
    }

    private func expireClients() {
        let now = Date()
        let expired = clients.filter { _, client in
            now.timeIntervalSince(client.lastProgress) > 5
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
        let status = Status(running: running, error: error)
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }
}

