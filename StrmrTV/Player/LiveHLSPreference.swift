import Foundation

/// Live TV's remembered "this provider needs HLS" (Expo `livePlaybackPreference`). When a
/// direct stream won't start, the live player retries once as an HLS session; once that has
/// played for a while the choice is kept on this device for the server and live source, and
/// later tunes of that source ask for HLS at once. Likewise a source whose fast live join kept
/// running dry on two tunes (`+JoinProfile`) is remembered as needing the standard, deeper join. Settings ›
/// Reset Live TV Playback clears both.
@MainActor
enum LiveHLSPreference {
    /// The server and live source a preference belongs to.
    struct Scope: Hashable {
        let server: String
        let sourceID: String
    }

    private static let prefix = "live.hlsPreference.v1:"
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

    static func remember(_ scope: Scope) {
        defaults.set("hls", forKey: key(scope))
    }

    static func prefersStandardJoin(_ scope: Scope) -> Bool {
        defaults.string(forKey: key(scope, prefix: joinPrefix)) == "standard"
    }

    /// A tune of this source ran dry under the fast join. The first time only marks the source;
    /// a second (on a later tune) remembers the standard join. True once it is remembered.
    @discardableResult
    static func noteFastJoinRanDry(_ scope: Scope) -> Bool {
        let key = key(scope, prefix: joinPrefix)
        let standard = defaults.string(forKey: key) != nil
        defaults.set(standard ? "standard" : "ranDry", forKey: key)
        return standard
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
