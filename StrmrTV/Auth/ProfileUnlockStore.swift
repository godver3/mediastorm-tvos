import Foundation

/// Server-issued profile unlock tokens (`POST /api/users/{id}/pin/verify`), one per
/// profile. They are bound to the account session on the server, so they live in the
/// Keychain next to it, survive a token refresh unchanged and are dropped with it.
struct ProfileUnlockStore {
    struct Unlock: Codable, Equatable {
        var token: String
        /// Nil when the server gave no expiry (unlock lasts as long as the session).
        var expiresAt: Date?

        var isExpired: Bool { expiresAt.map { $0 <= Date() } ?? false }
    }

    private static let account = "profileUnlocks"
    private var unlocks: [String: Unlock]

    init() {
        let stored = Keychain.read(Self.account).flatMap { try? JSONDecoder().decode([String: Unlock].self, from: $0) }
        unlocks = stored ?? [:]
        if pruneExpired() { save() }
    }

    /// The live token for a profile, dropping it once expired.
    mutating func token(for profileID: String) -> String? {
        guard let unlock = unlocks[profileID] else { return nil }
        if unlock.isExpired {
            remove(profileID)
            return nil
        }
        return unlock.token
    }

    mutating func set(_ token: String, expiresAt: String?, for profileID: String) {
        let date = expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        unlocks[profileID] = Unlock(token: token, expiresAt: date)
        save()
    }

    mutating func remove(_ profileID: String) {
        guard unlocks.removeValue(forKey: profileID) != nil else { return }
        save()
    }

    /// Profile switch: only the active profile stays unlocked.
    mutating func keepOnly(_ profileID: String) {
        let kept = unlocks.filter { $0.key == profileID && !$0.value.isExpired }
        guard kept != unlocks else { return }
        unlocks = kept
        save()
    }

    mutating func removeAll() {
        unlocks = [:]
        Keychain.delete(Self.account)
    }

    @discardableResult
    private mutating func pruneExpired() -> Bool {
        let before = unlocks.count
        unlocks = unlocks.filter { !$0.value.isExpired }
        return unlocks.count != before
    }

    private func save() {
        if unlocks.isEmpty {
            Keychain.delete(Self.account)
        } else if let data = try? JSONEncoder().encode(unlocks) {
            Keychain.write(data, account: Self.account)
        }
    }
}
