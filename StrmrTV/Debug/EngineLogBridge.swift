import AetherEngine
import Foundation

/// Mirrors AetherEngine's diagnostic lines into the app log under `[engine]`, so a submitted log
/// shows what the engine did (a live re-cut, an audio timestamp gap, an output change) and not
/// only what the player saw. The engine hands over its info lines with credentials already
/// stripped; its per-segment trace stays in OSLog, and the loopback server's line per request is
/// left out (a live session makes several a segment, and they would push the rest out of the
/// 4 MB file). A burst is capped at `limit` lines per `window`, and the count dropped is logged
/// when the next window opens.
enum EngineLogBridge {
    private static let limit = 60
    private static let window: TimeInterval = 10
    private static let log = AppLog(category: "engine")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var windowStart = Date.distantPast
    nonisolated(unsafe) private static var lines = 0
    nonisolated(unsafe) private static var dropped = 0

    static func install() {
        EngineLog.handler = { line in
            guard !line.hasPrefix("[HLSLocalServer] GET ") else { return }
            let (pass, droppedBefore) = admit()
            if droppedBefore > 0 { log.info("(\(droppedBefore) engine lines dropped)") }
            if pass { log.info(line) }
        }
    }

    /// Whether this line fits the current window, and how many the previous window dropped.
    private static func admit() -> (Bool, Int) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        var droppedBefore = 0
        if now.timeIntervalSince(windowStart) >= window {
            droppedBefore = dropped
            windowStart = now
            lines = 0
            dropped = 0
        }
        guard lines < limit else {
            dropped += 1
            return (false, droppedBefore)
        }
        lines += 1
        return (true, droppedBefore)
    }
}
