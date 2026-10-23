import Foundation

/// A signed-in account session. Persisted in the Keychain, never in UserDefaults.
struct AuthSession: Codable, Equatable {
    var token: String
    var expiresAt: Date?
    var accountID: String
    var username: String

    init(_ login: LoginResponse) {
        token = login.token
        expiresAt = login.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        accountID = login.accountId
        username = login.username
    }

    /// Refresh this far ahead of expiry. Sessions last 30 days (90 with rememberMe),
    /// and each refresh rotates the token, so only refresh near the end.
    static let refreshWindow: TimeInterval = 7 * 24 * 3600

    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < Self.refreshWindow
    }

    // MARK: Keychain

    private static let account = "session"

    static func load() -> AuthSession? {
        Keychain.read(account).flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) }
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { Keychain.write(data, account: Self.account) }
    }

    static func clear() {
        Keychain.delete(account)
    }
}
