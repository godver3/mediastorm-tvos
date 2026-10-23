import Foundation
import Network

/// A tiny HTTP/1.0 server for the remote driver: one GET per connection, closed after the
/// reply. Requests are queued for the test's main thread (XCUITest calls must run there and
/// must not re-enter), which drains them with `next()` between run-loop turns.
final class DriverServer: @unchecked Sendable {
    struct Request {
        let path: String
        let query: [String: String]
        let respond: @Sendable (Response) -> Void
    }

    struct Response {
        var status = 200
        var contentType = "text/plain; charset=utf-8"
        var body = Data()

        static func text(_ text: String, status: Int = 200) -> Response {
            Response(status: status, body: Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
        }

        static func json(_ object: Any) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return Response(contentType: "application/json", body: data + Data("\n".utf8))
        }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "strmr.driver.server")
    private let lock = NSLock()
    private var pending: [Request] = []

    init(port: UInt16) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    func start() { listener.start(queue: queue) }
    func stop() { listener.cancel() }

    /// The oldest queued request, if any. Main thread only.
    func next() -> Request? {
        lock.lock()
        defer { lock.unlock() }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.enqueue(String(decoding: buffer[..<end.lowerBound], as: UTF8.self), connection)
            } else if done || error != nil || buffer.count > 65536 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func enqueue(_ head: String, _ connection: NWConnection) {
        let target = head.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let request = Request(path: components?.path ?? target, query: query) { [weak self] response in
            self?.queue.async { Self.send(response, on: connection) }
        }
        lock.lock()
        pending.append(request)
        lock.unlock()
    }

    private static func send(_ response: Response, on connection: NWConnection) {
        let head = "HTTP/1.0 \(response.status) \(response.status == 200 ? "OK" : "Error")\r\n"
            + "Content-Type: \(response.contentType)\r\nContent-Length: \(response.body.count)\r\n"
            + "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
