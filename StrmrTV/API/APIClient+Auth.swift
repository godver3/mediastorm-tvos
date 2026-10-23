import Foundation

/// Connection, sign-in, profile and device-registration endpoints.
extension APIClient {
    /// `GET /health` on a candidate server, without changing `baseURL`. Throws a
    /// message suitable for the server screen.
    func checkHealth(of server: URL) async throws {
        var req = URLRequest(url: server.appending(path: "/health"))
        req.timeoutInterval = 8
        req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
        let host = server.host() ?? server.absoluteString
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let error as URLError {
            throw APIError.notReady(Self.describe(error, host: host))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        struct Health: Decodable { let status: String? }
        guard status == 200, (try? decoder.decode(Health.self, from: data))?.status == "ok" else {
            throw APIError.notReady(
                String(localized: "\(host) answered, but it doesn't look like a MediaStorm server (HTTP \(status)). Check the address and port.")
            )
        }
    }

    private static func describe(_ error: URLError, host: String) -> String {
        switch error.code {
        case .timedOut:
            String(localized: "\(host) didn't respond in time. Check that the server is running and reachable from this Apple TV.")
        case .cannotFindHost, .dnsLookupFailed:
            String(localized: "Couldn't find \(host). Check the address.")
        case .cannotConnectToHost:
            String(localized: "\(host) refused the connection. Check the port and that the server is running.")
        case .notConnectedToInternet, .networkConnectionLost:
            String(localized: "This Apple TV isn't connected to a network.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            String(localized: "Couldn't make a secure connection to \(host). Try http:// if the server has no certificate.")
        default:
            error.localizedDescription
        }
    }

    /// `GET /api/version` on a candidate server (a discovered one), without changing
    /// `baseURL`.
    func checkVersion(of server: URL) async throws -> ServerVersion {
        var req = URLRequest(url: server.appending(path: "/api/version"))
        req.timeoutInterval = 6
        req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
        let host = server.host() ?? server.absoluteString
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let version = try? decoder.decode(ServerVersion.self, from: data)
            else {
                throw APIError.notReady(String(localized: "\(host) answered, but it doesn't look like a MediaStorm server."))
            }
            return version
        } catch let error as URLError {
            throw APIError.notReady(Self.describe(error, host: host))
        }
    }

    /// `GET /api/version` (public); nil on older servers or errors.
    func serverVersion() async -> ServerVersion? {
        try? await send("GET", "/api/version", authorized: false, timeout: 8)
    }

    /// `GET /api/branding` (public): the admin's uploaded logos, if any.
    func publicBranding() async -> PublicBranding? {
        let response: PublicBrandingResponse? = try? await send("GET", "/api/branding", authorized: false, timeout: 8)
        return response?.branding
    }

    func login(username: String, password: String) async throws -> AuthSession {
        let data = try await sendRaw(
            "POST", "/api/auth/login",
            jsonObject: ["username": username, "password": password, "rememberMe": true],
            authorized: false
        )
        let session = AuthSession(try decoder.decode(LoginResponse.self, from: data))
        // Unlocks belong to the previous session; the server no longer honours them.
        profileUnlocks.removeAll()
        self.session = session
        return session
    }

    /// Revokes the session on the server (best effort) and forgets it locally.
    func logout() async {
        if let token {
            var req = URLRequest(url: url("/api/auth/logout"))
            req.httpMethod = "POST"
            req.timeoutInterval = 5
            req.setValue(Config.clientID, forHTTPHeaderField: "X-Client-ID")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: req)
        }
        forgetSession()
    }

    func profiles() async throws -> [Profile] {
        try await send("GET", "/api/users")
    }

    /// `POST /api/users/{id}/pin/verify`; false for a wrong (or empty) PIN. Stores the
    /// unlock token current servers return (older ones only answer `valid`).
    func verifyPIN(_ pin: String, profileID: String) async throws -> Bool {
        struct Verified: Decodable {
            let valid: Bool
            let unlockToken: String?
            let expiresAt: String?
        }
        do {
            let result: Verified = try await send(
                "POST", "/api/users/\(Self.segment(profileID))/pin/verify", body: ["pin": pin],
                promptOnLock: false
            )
            if result.valid, let token = result.unlockToken, !token.isEmpty {
                profileUnlocks.set(token, expiresAt: result.expiresAt, for: profileID)
            }
            return result.valid
        } catch let error as APIError where error.isWrongPIN {
            return false
        }
    }

    /// Public profile image (`GET /api/users/{id}/icon`) when the profile has one.
    func iconURL(for profile: Profile) -> URL? {
        guard profile.hasIcon == true else { return nil }
        return url("/api/users/\(Self.segment(profile.id))/icon", query: ["v": profile.iconUrl ?? ""])
    }

    func registerClient(profileID: String) async throws {
        try await sendRaw("POST", "/api/clients/register", jsonObject: Config.registration(profileID: profileID))
    }
}
