import Foundation

/// A non-2xx response. Current servers answer with `{"error": "...", "code": "..."}`
/// (plus extras such as `profileId`); older ones send plain text or only `error`.
struct HTTPFailure: Sendable {
    let status: Int
    let body: String
    /// Stable machine code (`APIError.Code`); nil from older servers.
    let code: String?
    /// The human-readable `error` (or `message`) field.
    let message: String?
    /// `profileId` from a `profile_locked` body.
    let profileID: String?
    /// Seconds from `Retry-After`, when sent.
    let retryAfter: TimeInterval?

    init(status: Int, data: Data, headers: [AnyHashable: Any] = [:]) {
        self.status = status
        body = String(decoding: data, as: UTF8.self)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        code = (json?["code"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        message = (json?["message"] as? String) ?? (json?["error"] as? String)
        profileID = json?["profileId"] as? String
        retryAfter = Self.retryAfter(headers)
    }

    private static func retryAfter(_ headers: [AnyHashable: Any]) -> TimeInterval? {
        let value = headers.first { ($0.key as? String)?.caseInsensitiveCompare("Retry-After") == .orderedSame }?.value
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let seconds = TimeInterval(text) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text).map { max(0, $0.timeIntervalSinceNow) }
    }
}

enum APIError: LocalizedError {
    case http(HTTPFailure)
    case notReady(String)
    /// The session is gone and could not be refreshed; the app returns to sign-in.
    case signedOut

    /// Stable `code` values from the server's error envelope.
    enum Code {
        static let unauthorized = "unauthorized"
        static let sessionExpired = "session_expired"
        static let accountExpired = "account_expired"
        static let invalidCredentials = "invalid_credentials"
        static let passwordInvalid = "password_invalid"
        static let pinInvalid = "pin_invalid"
        static let pinRequired = "pin_required"
        static let profileLocked = "profile_locked"
        static let forbidden = "forbidden"
        static let masterRequired = "master_required"
        static let profileNotFound = "profile_not_found"
        static let rateLimited = "rate_limited"
        static let defaultPassword = "default_password"
    }

    var errorDescription: String? {
        switch self {
        case let .http(failure):
            if isRateLimited { return Self.rateLimitMessage(failure.retryAfter) }
            if failure.code == Code.profileLocked { return String(localized: "This profile is locked. Enter its PIN to continue.") }
            return Self.serverMessage(failure) ?? "Server returned \(failure.status): \(failure.body.prefix(200))"
        case let .notReady(msg): return msg
        case .signedOut: return String(localized: "Your session has ended. Sign in again.")
        }
    }

    var failure: HTTPFailure? {
        if case let .http(failure) = self { return failure }
        return nil
    }

    var statusCode: Int? { failure?.status }
    var code: String? { failure?.code }

    /// Whether this rejects the session itself, so a refresh (or sign-out) is due.
    /// Coded answers decide; without a code (older servers) any 401 counts, except a
    /// wrong-PIN reply, which those servers mark only by the word "PIN".
    var invalidatesSession: Bool {
        guard let failure, failure.status == 401 || failure.code != nil else { return false }
        if let code = failure.code {
            return [Code.unauthorized, Code.sessionExpired, Code.accountExpired].contains(code)
        }
        return !isWrongPIN
    }

    /// Wrong or missing profile PIN; the session is fine.
    var isWrongPIN: Bool {
        guard let failure else { return false }
        if let code = failure.code { return code == Code.pinInvalid || code == Code.pinRequired }
        return failure.status == 401 && failure.body.localizedCaseInsensitiveContains("pin")
    }

    var isProfileLocked: Bool { code == Code.profileLocked }

    var isRateLimited: Bool {
        guard let failure else { return false }
        return failure.code.map { $0 == Code.rateLimited } ?? (failure.status == 429)
    }

    /// The admin account still has the default password (HTTP 428).
    var isDefaultPassword: Bool {
        guard let failure else { return false }
        return failure.code.map { $0 == Code.defaultPassword } ?? (failure.status == 428)
    }

    static func rateLimitMessage(_ retryAfter: TimeInterval?) -> String {
        guard let retryAfter, retryAfter > 0 else {
            return String(localized: "Too many attempts. Wait a minute and try again.")
        }
        let seconds = Int(retryAfter.rounded(.up))
        if seconds >= 90 {
            let minutes = Int((Double(seconds) / 60).rounded(.up))
            return String(localized: "Too many attempts. Try again in \(minutes) minutes.")
        }
        return String(localized: "Too many attempts. Try again in \(seconds) seconds.")
    }

    /// The envelope's message, or a short plain-text body.
    private static func serverMessage(_ failure: HTTPFailure) -> String? {
        if let message = failure.message, !message.isEmpty { return message }
        let trimmed = failure.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.count > 160 || trimmed.hasPrefix("<") || trimmed.hasPrefix("{") ? nil : trimmed
    }
}
