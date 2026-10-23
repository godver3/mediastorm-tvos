import Foundation
import os

/// `os.Logger` that also appends each line to `Library/Caches/strmr.log` in the app container,
/// so device logs can be pulled without root:
///
///     xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
///       --domain-identifier com.strmr.app.nx --source Library/Caches/strmr.log --destination strmr.log
struct AppLog: Sendable {
    private let logger: Logger
    private let category: String

    init(category: String) {
        logger = Logger(subsystem: "com.strmr.app.nx", category: category)
        self.category = category
    }

    func debug(_ message: String) { logger.debug("\(message, privacy: .public)"); LogFile.shared.append("D", category, message) }
    func info(_ message: String) { logger.info("\(message, privacy: .public)"); LogFile.shared.append("I", category, message) }
    func notice(_ message: String) { logger.notice("\(message, privacy: .public)"); LogFile.shared.append("N", category, message) }
    func error(_ message: String) { logger.error("\(message, privacy: .public)"); LogFile.shared.append("E", category, message) }
}

/// The shared log file, written on a serial queue. Rotated to `strmr.log.1` past 4 MB.
final class LogFile: @unchecked Sendable {
    static let shared = LogFile()

    private static let maxBytes: UInt64 = 4 << 20
    private let queue = DispatchQueue(label: "com.strmr.app.nx.logfile")
    private let url: URL
    private var handle: FileHandle?
    /// Bytes appended since launch, so `LogUploader` can tell whether anything is new.
    private var written: UInt64 = 0
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        url = caches.appendingPathComponent("strmr.log")
    }

    func append(_ level: String, _ category: String, _ message: String) {
        let date = Date()
        queue.async { [self] in
            let line = "\(formatter.string(from: date)) \(level) [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            let handle = openHandle()
            handle?.write(data)
            written += UInt64(data.count)
            if let size = try? handle?.offset(), size > Self.maxBytes { rotate() }
        }
    }

    /// The newest `maxBytes` of the log (the rotated file first, then the current one), cut
    /// at a line start, and the byte count written so far. Read on the writer's queue, so it
    /// never sees half a line.
    func tail(maxBytes: Int) async -> (text: String, written: UInt64) {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                try? handle?.synchronize()
                var data = (try? Data(contentsOf: url.appendingPathExtension("1"))) ?? Data()
                data.append((try? Data(contentsOf: url)) ?? Data())
                if data.count > maxBytes {
                    data = data.suffix(maxBytes)
                    if let newline = data.firstIndex(of: 0x0A) { data = data[data.index(after: newline)...] }
                }
                continuation.resume(returning: (String(decoding: data, as: UTF8.self), written))
            }
        }
    }

    private func openHandle() -> FileHandle? {
        if let handle { return handle }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let old = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
