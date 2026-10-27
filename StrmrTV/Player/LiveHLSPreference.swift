import Foundation

/// Live TV's remembered "this provider needs HLS" (Expo `livePlaybackPreference`). When a
/// direct stream won't start, the live player retries once as an HLS session; once that has
/// played for a while the choice is kept on this device for the server and live source, and
/// later tunes of that source ask for HLS at once, unless a direct stream of the source has
/// played here before, which rules the fallback out for it. Settings › Reset Live TV Playback
/// clears both marks, along with the join choice older builds remembered (`joinPrefix`).
@MainActor
enum LiveHLSPreference {
    /// The server and live source a preference belongs to.
    struct Scope: Hashable {
        let server: String
        let sourceID: String
    }

    private static let prefix = "live.hlsPreference.v1:"
    /// Older builds' remembered standard join; only `resetAll` still reads it.
    private static let joinPrefix = "live.joinPreference.v1:"
    private static var defaults: UserDefaults { .standard }

    private static var serverID: String?
    /// The base URL `serverID` was looked up on; another server is looked up afresh.
    private static var identityBase: URL?
    private static var identityTask: Task<String?, Never>?
    private static var retryAt = Date.distantPast

    /// The channel's scope. The server identity is cached per base URL, so after a relaunch or
    /// an iroh re-pairing (a new loopback URL) the first tune waits for the lookup (5 s at most);
    /// answering from the empty cache instead missed every remembered source.
    static func scope(for channel: LiveChannel) async -> Scope? {
        guard let source = channel.sourceId?.trimmingCharacters(in: .whitespaces), !source.isEmpty else { return nil }
        return await identity().map { Scope(server: $0, sourceID: source) }
    }

    static func prefersHLS(_ scope: Scope) -> Bool {
        defaults.string(forKey: key(scope)) == "hls"
    }

    /// Never over a source whose direct stream has played: a direct stream that worked once and
    /// then struggles is a provider having a bad moment, and the server's HLS session reads the
    /// same provider.
    static func remember(_ scope: Scope) {
        guard !directWorked(scope) else { return }
        defaults.set("hls", forKey: key(scope))
    }

    /// A direct stream of this source showed a frame on this device.
    static func directWorked(_ scope: Scope) -> Bool {
        defaults.string(forKey: key(scope)) == "direct"
    }

    static func rememberDirectWorked(_ scope: Scope) {
        defaults.set("direct", forKey: key(scope))
    }

    /// Forgets every remembered source; returns how many there were.
    @discardableResult
    static func resetAll() -> Int {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) || $0.hasPrefix(joinPrefix) }
        keys.forEach(defaults.removeObject(forKey:))
        return keys.count
    }

    private static func key(_ scope: Scope, prefix: String = Self.prefix) -> String {
        let allowed = CharacterSet.alphanumerics
        let server = scope.server.addingPercentEncoding(withAllowedCharacters: allowed) ?? scope.server
        let source = scope.sourceID.addingPercentEncoding(withAllowedCharacters: allowed) ?? scope.sourceID
        return "\(prefix)\(server):\(source)"
    }

    private static func identity() async -> String? {
        resetIfServerChanged()
        if let serverID { return serverID }
        return await startLookup()?.value
    }

    private static func resetIfServerChanged() {
        let base = APIClient.shared.baseURL
        guard identityBase != base else { return }
        identityBase = base
        serverID = nil
        identityTask = nil
        retryAt = .distantPast
    }

    /// One lookup at a time; a failed one isn't retried for five minutes.
    private static func startLookup() -> Task<String?, Never>? {
        if let identityTask { return identityTask }
        guard Date() >= retryAt else { return nil }
        let base = identityBase
        let task = Task<String?, Never> {
            let id = try? await APIClient.shared.serverIdentity()
            guard identityBase == base else { return nil }
            if let id, !id.isEmpty {
                serverID = id
            } else {
                retryAt = Date().addingTimeInterval(5 * 60)
            }
            identityTask = nil
            return serverID
        }
        identityTask = task
        return task
    }
}
