import Foundation

@_silgen_name("iroh_ios_bridge_drain_logs")
private func iroh_drain_logs() -> UnsafeMutablePointer<CChar>?
@_silgen_name("iroh_ios_bridge_free_string")
private func iroh_free_logs(_ value: UnsafeMutablePointer<CChar>?)

private let log = AppLog(category: "Iroh")

/// Copies the iroh bridge's own log lines (connect, selected path, `path changed … from=…`,
/// reconnects, failures) into `strmr.log`, where shared logs pick them up. The bridge keeps
/// only its last 500 lines, so it is drained every couple of seconds once a proxy starts.
/// Without this an iPhone log cannot say whether a slow session ran direct or through a relay.
enum IrohBridgeLog {
    private static let interval: Duration = .seconds(2)
    /// Per-request proxy lines: several per HTTP call, and they would bury the path lines.
    private static let noise = [
        "local proxy request id=", "local proxy opened stream id=", "local proxy response id=",
        "local proxy first body id=", "local proxy complete id=",
    ]

    @MainActor private static var drainer: Task<Void, Never>?

    /// Starts the drain loop; later calls do nothing.
    @MainActor static func start() {
        guard drainer == nil else { return }
        drainer = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                drain()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private static func drain() {
        let pointer = iroh_drain_logs()
        defer { iroh_free_logs(pointer) }
        guard let pointer else { return }
        let text = String(cString: pointer)
        guard !text.isEmpty else { return }
        for line in text.split(separator: "\n") where !noise.contains(where: line.contains) {
            log.info(String(line))
        }
    }
}
