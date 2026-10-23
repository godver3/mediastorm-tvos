import Foundation

extension APIClient {
    /// `POST /api/logs/frontend`: the server keeps it as this device's latest log snapshot.
    func uploadLogs(_ text: String, reason: String) async throws {
        let marker = "\(ISO8601DateFormatter().string(from: Date())) I [LogUpload] snapshot reason=\(reason) bytes=\(text.utf8.count)"
        try await sendRaw("POST", "/api/logs/frontend", jsonObject: [
            "frontendLogs": text + marker,
            "deviceType": Config.deviceType,
            "os": Config.osVersion,
            "appVersion": Config.fullVersion,
        ], promptOnLock: false, timeout: 30)
    }
}
