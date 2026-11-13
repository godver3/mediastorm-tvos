#if os(iOS)
import Foundation

/// Profile management on the phone: the `/api/users` calls the Expo app's profile screens and
/// the admin UI make (create needs the account password; the rest edit one profile).
extension APIClient {
    /// `GET /api/stream-usage`: the account's concurrent streams against its limit; nil when
    /// the server sets no limit.
    struct StreamUsage: Decodable, Sendable {
        let currentStreams: Int
        let maxStreams: Int
    }

    func streamUsage(profileID: String) async -> StreamUsage? {
        let usage: StreamUsage? = try? await send("GET", "/api/stream-usage", query: ["profileId": profileID],
                                                  promptOnLock: false, timeout: 10)
        guard let usage, usage.maxStreams > 0 else { return nil }
        return usage
    }

    /// `POST /api/auth/verify-password`: whether `password` is the signed-in account's.
    func verifyAccountPassword(_ password: String) async throws -> Bool {
        struct Verified: Decodable { let verified: Bool }
        do {
            let result: Verified = try await send("POST", "/api/auth/verify-password", body: ["password": password])
            return result.verified
        } catch let error as APIError where error.code == APIError.Code.passwordInvalid {
            return false
        }
    }

    /// Verify the password first (`verifyAccountPassword`): a wrong one here is an uncoded 401,
    /// which the client takes for an ended session.
    @discardableResult
    func createProfile(name: String, password: String) async throws -> Profile {
        try await send("POST", "/api/users", body: ["name": name, "password": password])
    }

    @discardableResult
    func renameProfile(_ id: String, to name: String) async throws -> Profile {
        try await send("PATCH", "/api/users/\(Self.segment(id))", body: ["name": name])
    }

    /// `#RRGGBB`, or empty for the default colour.
    @discardableResult
    func setProfileColor(_ id: String, _ color: String) async throws -> Profile {
        try await send("PUT", "/api/users/\(Self.segment(id))/color", body: ["color": color])
    }

    // Kids profile, PIN and delete are parental controls: for an ordinary account the server
    // answers `parent_authorization_required` until the account password comes with the change
    // (`ParentAuthorizationPrompt` asks for it). An administrator account needs none.

    @discardableResult
    func setKidsProfile(_ id: String, _ isKids: Bool, accountPassword: String? = nil) async throws -> Profile {
        try await send("PUT", "/api/users/\(Self.segment(id))/kids-profile", jsonObject: ["isKidsProfile": isKids],
                       headers: Self.parentAuthorization(accountPassword))
    }

    func setProfilePIN(_ id: String, _ pin: String, accountPassword: String? = nil) async throws {
        try await sendRaw("PUT", "/api/users/\(Self.segment(id))/pin", body: ["pin": pin],
                          headers: Self.parentAuthorization(accountPassword))
    }

    func clearProfilePIN(_ id: String, accountPassword: String? = nil) async throws {
        try await sendRaw("DELETE", "/api/users/\(Self.segment(id))/pin", headers: Self.parentAuthorization(accountPassword))
    }

    func deleteProfile(_ id: String, accountPassword: String? = nil) async throws {
        try await sendRaw("DELETE", "/api/users/\(Self.segment(id))", headers: Self.parentAuthorization(accountPassword))
    }

    /// `X-Account-Password`, Base64 so any character (and surrounding spaces) survives a header.
    private static func parentAuthorization(_ password: String?) -> [String: String] {
        guard let password, !password.isEmpty else { return [:] }
        return ["X-Account-Password": "base64:" + Data(password.utf8).base64EncodedString()]
    }
}
#endif
