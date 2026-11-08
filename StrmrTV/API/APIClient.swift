import Foundation

/// Thin client for the strmr backend. Holds the server, the account session (with
/// refresh) and the active profile; `AppSession` decides which of those are set.
@MainActor
final class APIClient: ObservableObject {
    static let shared = APIClient()

    /// Server origin (plus any reverse-proxy path), without `/api`.
    var baseURL = URL(string: "http://127.0.0.1:\(ServerAddress.defaultPort)")!
    /// Over iroh remote access: the pairing credential, sent with every request
    /// (`X-Remote-Access-Credential`) beside `X-Client-ID`.
    var remoteCredential: String?
    /// Over remote access: brings the tunnel back after a transport failure and returns its
    /// base URL (the proxy's port can change). Set by `AppSession`.
    var recoverTransport: (() async -> URL?)?
    /// Told after each request whether the server answered (any HTTP status) or the transport
    /// failed (the `URLError`); iOS uses it to notice a lost connection. Nil on tvOS.
    var onTransportResult: ((URLError?) -> Void)?
    /// Persisted to the Keychain whenever it changes (login, refresh).
    var session: AuthSession? {
        didSet { if let session, session != oldValue { session.save() } }
    }
    private(set) var profileID: String = "default"
    /// Display name of the active profile, for the dashboard's stream attribution.
    private(set) var profileName: String?
    /// Called when the session is rejected and a refresh fails.
    var onSignedOut: (() -> Void)?
    /// Asked when a request hits a locked profile (`403 profile_locked`): prompt for
    /// the PIN and return true once it is unlocked, so the request is retried.
    var onProfileLocked: ((String) async -> Bool)?
    /// Unlock tokens for PIN-protected profiles, sent as `X-Profile-Unlock`.
    var profileUnlocks = ProfileUnlockStore()

    private var refreshTask: Task<RefreshOutcome, Never>?

    /// API calls get their own connections: every one goes to one host (the server, or the
    /// iroh proxy), and the shared session's 6 per host would queue Continue Watching
    /// behind a Home view's slow list rows.
    private static let http: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        return URLSession(configuration: config)
    }()

    let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    var token: String? { session?.token }

    func activate(profileID: String, profileName: String? = nil) {
        self.profileID = profileID
        self.profileName = profileName
        profileUnlocks.keepOnly(profileID)
    }

    /// Percent-encodes one path segment (a profile id may contain anything).
    static func segment(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// RFC 3986 unreserved characters; everything else is escaped in segments and
    /// query values (a bare `+` would read as a space on the server).
    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    var profilePath: String { "/api/users/\(Self.segment(profileID))" }

    static let unlockHeader = "X-Profile-Unlock"
    /// Lists, search and Top 10: the GETs that carry series episode counts.
    private static let countsPaths = ["/display-list", "/api/search", "/api/discover/top-ten"]

    // MARK: Plumbing

    func send<T: Decodable & Sendable>(
        _ method: String, _ path: String,
        query: [String: String] = [:],
        body: [String: String]? = nil,
        jsonObject: [String: Any]? = nil,
        authorized: Bool = true,
        promptOnLock: Bool = true,
        timeout: TimeInterval = 30,
        headers: [String: String] = [:]
    ) async throws -> T {
        let data = try await sendRaw(method, path, query: query, body: body, jsonObject: jsonObject,
                                     authorized: authorized, promptOnLock: promptOnLock, timeout: timeout,
                                     headers: headers)
        return try await Self.decode(data)
    }

    /// Decodes off the main actor: Home's rows, the calendar and Continue Watching all
    /// arrive at launch, and decoding them here dropped frames while focus moved.
    @concurrent
    private nonisolated static func decode<T: Decodable & Sendable>(_ data: Data) async throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    /// Authorized calls refresh the session ahead of expiry, and when the server says
    /// the session is gone (`unauthorized` / `session_expired` / `account_expired`, or
    /// a bare 401 from older servers) refresh once and retry; if that fails the app is
    /// signed out (`onSignedOut`). Other coded 401s (a wrong PIN) are thrown as-is.
    ///
    /// Requests naming a profile carry its unlock token. A `profile_locked` answer
    /// asks `onProfileLocked` for the PIN and retries once; `promptOnLock: false`
    /// (background calls, e.g. during playback) just throws.
    @discardableResult
    func sendRaw(
        _ method: String, _ path: String,
        query: [String: String] = [:],
        body: [String: String]? = nil,
        jsonObject: [String: Any]? = nil,
        authorized: Bool = true,
        promptOnLock: Bool = true,
        timeout: TimeInterval = 30,
        encodedQuery: String? = nil,
        jsonArray: [[String: Any]]? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        #if DEBUG
        if method == "GET", let fixture = SportsFixtures.response(path: path) { return fixture }
        #endif
        var query = query
        // While cards show the unwatched count, lists ask the server to look up the episode
        // totals it hasn't cached yet (it sends the cached ones regardless), as Expo does.
        if method == "GET", Self.countsPaths.contains(where: path.hasSuffix), BadgeSettingsStore.shared.shows(.unwatchedCount) {
            query["includeUnwatchedCounts"] = "true"
        }
        var req = URLRequest(url: url(path, query: query, encodedQuery: encodedQuery))
        req.httpMethod = method
        req.timeoutInterval = timeout
        for (name, value) in headers { req.setValue(value, forHTTPHeaderField: name) }
        req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
        if let remoteCredential { req.setValue(remoteCredential, forHTTPHeaderField: "X-Remote-Access-Credential") }
        var bodyFields: [String: Any] = [:]
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
            bodyFields = body
        } else if let jsonObject {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonObject)
            bodyFields = jsonObject
        } else if let jsonArray {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: jsonArray)
        }
        guard authorized else { return try await perform(req) }

        let named = Self.profileIDs(path: path, query: query, body: bodyFields)
        applyUnlocks(to: &req, profiles: named)
        do {
            return try await performAuthorized(req)
        } catch let error as APIError where error.isProfileLocked {
            let locked = error.failure?.profileID ?? named.first ?? profileID
            profileUnlocks.remove(locked)  // missing, expired or revoked
            guard promptOnLock, let onProfileLocked, await onProfileLocked(locked) else { throw error }
            applyUnlocks(to: &req, profiles: named.contains(locked) ? named : named + [locked])
            return try await performAuthorized(req)
        }
    }

    private func performAuthorized(_ request: URLRequest) async throws -> Data {
        var req = request
        if session?.needsRefresh == true, await refreshSession() == .rejected {
            signOutLocally()
            throw APIError.signedOut
        }
        guard let token else { throw APIError.signedOut }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            return try await perform(req)
        } catch let error as APIError where error.invalidatesSession {
            switch await refreshSession() {
            case .refreshed: break
            case .failed: throw error
            case .rejected:
                signOutLocally()
                throw APIError.signedOut
            }
            guard let fresh = self.token else { throw APIError.signedOut }
            req.setValue("Bearer \(fresh)", forHTTPHeaderField: "Authorization")
            return try await perform(req)
        }
    }

    /// `X-Profile-Unlock` with every stored token for the profiles a request names.
    private func applyUnlocks(to req: inout URLRequest, profiles: [String]) {
        let tokens = profiles.compactMap { profileUnlocks.token(for: $0) }
        req.setValue(tokens.isEmpty ? nil : tokens.joined(separator: ","), forHTTPHeaderField: Self.unlockHeader)
    }

    /// Profile ids a request names, the way the server's PIN middleware finds them:
    /// `/api/users/{id}/…` or `/api/profiles/{id}/…`, `profileId` / `userId` in the
    /// query, and top-level `profileId` / `userId` in a JSON body.
    static func profileIDs(path: String, query: [String: String], body: [String: Any]) -> [String] {
        var ids: [String] = []
        func add(_ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty, !ids.contains(value) else { return }
            ids.append(value)
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 3, parts[0] == "api", ["users", "profiles"].contains(parts[1]) {
            add(parts[2].removingPercentEncoding ?? parts[2])
        }
        for key in ["profileId", "userId"] {
            add(query[key])
            add(body[key] as? String)
        }
        return ids
    }

    /// `path` must already be percent-encoded (use `segment(_:)` for ids); query
    /// values are encoded here. `encodedQuery` (already encoded, e.g. with repeated keys)
    /// is appended as is.
    func url(_ path: String, query: [String: String] = [:], encodedQuery: String? = nil) -> URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var base = comps.percentEncodedPath
        while base.hasSuffix("/") { base.removeLast() }
        comps.percentEncodedPath = base + path
        if !query.isEmpty {
            comps.percentEncodedQuery = query.sorted { $0.key < $1.key }
                .map { "\(Self.segment($0.key))=\(Self.segment($0.value))" }
                .joined(separator: "&")
        }
        if let encodedQuery, !encodedQuery.isEmpty {
            comps.percentEncodedQuery = [comps.percentEncodedQuery, encodedQuery].compactMap { $0 }.joined(separator: "&")
        }
        return comps.url!
    }

    private func perform(_ req: URLRequest, retried: Bool = false) async throws -> Data {
        let data: Data, response: URLResponse
        do {
            #if DEBUG
            if let simulated = DebugNetworkFault.error { throw simulated }
            #endif
            (data, response) = try await Self.http.data(for: req)
        } catch let error as URLError where !retried && remoteCredential != nil && Self.isTransportFailure(error) {
            // Through the iroh proxy, the first request after a sleep or a path change can fail
            // while the connection is re-established: reconnect, then retry once.
            guard let base = await recoverTransport?(), let retry = Self.rebased(req, onto: base) else {
                onTransportResult?(error)
                throw error
            }
            return try await perform(retry, retried: true)
        } catch let error as URLError {
            onTransportResult?(error)
            throw error
        }
        onTransportResult?(nil)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.http(HTTPFailure(status: status, data: data, headers: http?.allHeaderFields ?? [:]))
        }
        return data
    }

    private static func isTransportFailure(_ error: URLError) -> Bool {
        [.networkConnectionLost, .cannotConnectToHost, .timedOut, .notConnectedToInternet].contains(error.code)
    }

    /// `request` sent to `base`'s scheme, host and port instead.
    private static func rebased(_ request: URLRequest, onto base: URL) -> URLRequest? {
        guard let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = base.scheme
        components.host = base.host()
        components.port = base.port
        var retry = request
        retry.url = components.url
        return retry
    }

    enum RefreshOutcome { case refreshed, rejected, failed }

    /// `POST /api/auth/refresh`, coalesced so concurrent 401s share one rotation.
    /// `.rejected` means the server refused the session; `.failed` (network) keeps it.
    func refreshSession() async -> RefreshOutcome {
        if let refreshTask { return await refreshTask.value }
        guard let current = session else { return .rejected }
        let task = Task<RefreshOutcome, Never> { [weak self] in
            guard let self else { return .failed }
            var req = URLRequest(url: self.url("/api/auth/refresh"))
            req.httpMethod = "POST"
            req.timeoutInterval = 20
            req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
            req.setValue("Bearer \(current.token)", forHTTPHeaderField: "Authorization")
            do {
                let data = try await self.perform(req)
                self.session = AuthSession(try self.decoder.decode(LoginResponse.self, from: data))
                return .refreshed
            } catch let error as APIError where error.invalidatesSession || [403, 404].contains(error.statusCode ?? 0) {
                return .rejected
            } catch {
                return .failed
            }
        }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    func signOutLocally() {
        guard session != nil else { return }
        forgetSession()
        onSignedOut?()
    }

    /// Drops the session and the profile unlocks bound to it.
    func forgetSession() {
        session = nil
        AuthSession.clear()
        profileUnlocks.removeAll()
    }
}
