#if os(iOS)
import Foundation

private let log = AppLog(category: "Reconnect")

/// Low-volume connection breadcrumbs, as the Expo app's `reconnectJournal`: the last 60
/// events (network changes, route choices, retries), sanitized (no invites, URLs or tokens),
/// kept across launches so the session before a failure can be read in Connection settings.
/// Each is also written to the app log, which the log upload sends to the server.
@MainActor
enum MobileReconnectJournal {
    struct Entry: Codable, Hashable {
        let timestamp: Date
        let event: String
        let details: [String: String]?
    }

    private static let key = "strmr.mobile.reconnectJournal.v1"
    private static let maxEntries = 60
    private static let maxDetailLength = 240

    private(set) static var entries: [Entry] = load()

    static func record(_ event: String, _ details: [String: String] = [:]) {
        let clean = details.mapValues(sanitize)
        let entry = Entry(timestamp: Date(), event: event, details: clean.isEmpty ? nil : clean)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
        let suffix = clean.isEmpty ? "" : " " + clean.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        log.info("\(event)\(suffix)")
    }

    static func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return Array(saved.suffix(maxEntries))
    }

    /// Strips what the Expo journal strips: iroh invites, URLs, bearer tokens and secrets.
    static func sanitize(_ value: String) -> String {
        var text = value
        let rules: [(String, String)] = [
            (#"mshost-iroh-[^\s"']+"#, "[invite]"),
            (#"https?://[^\s"']+"#, "[url]"),
            (#"Bearer\s+[^\s"']+"#, "Bearer [redacted]"),
            (#"(?i)(token|password|api[_-]?key)(\s*[=:]\s*)[^\s,"'}]+"#, "$1$2[redacted]"),
        ]
        for (pattern, template) in rules {
            text = text.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
        }
        return String(text.prefix(maxDetailLength))
    }
}
#endif
