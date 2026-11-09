import Foundation

/// A recurring recording (`/api/live/recording-rules`): a title (or regex) the server matches
/// against the guide, on one channel or all of them (the Expo app's `RecordingRule`).
struct RecordingRule: Decodable, Identifiable, Hashable {
    let id: String
    let matchType: String
    let pattern: String
    let channelId: String?
    let tvgId: String?
    let channelName: String?
    let allChannels: Bool
    let enabled: Bool
    let newOnly: Bool
    let paddingBeforeSeconds: Int
    let paddingAfterSeconds: Int

    var isRegex: Bool { matchType == "regex" }

    private enum CodingKeys: String, CodingKey {
        case id, matchType, pattern, channelId, tvgId, channelName, allChannels, enabled, newOnly,
             paddingBeforeSeconds, paddingAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        matchType = try c.decodeIfPresent(String.self, forKey: .matchType) ?? "title"
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        channelId = try c.decodeIfPresent(String.self, forKey: .channelId)
        tvgId = try c.decodeIfPresent(String.self, forKey: .tvgId)
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName)
        allChannels = try c.decodeIfPresent(Bool.self, forKey: .allChannels) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        newOnly = try c.decodeIfPresent(Bool.self, forKey: .newOnly) ?? false
        paddingBeforeSeconds = try c.decodeIfPresent(Int.self, forKey: .paddingBeforeSeconds) ?? 0
        paddingAfterSeconds = try c.decodeIfPresent(Int.self, forKey: .paddingAfterSeconds) ?? 0
    }
}

/// The profile's default padding around new recordings (`/api/live/recording-settings`).
struct RecordingSettings: Codable, Hashable {
    var paddingBeforeSeconds: Int
    var paddingAfterSeconds: Int
}

private struct RecordingRulesResponse: Decodable {
    let rules: [RecordingRule]?
}

extension APIClient {
    func recordingRules() async throws -> [RecordingRule] {
        let response: RecordingRulesResponse = try await send("GET", "/api/live/recording-rules",
                                                              query: ["profileId": profileID])
        return response.rules ?? []
    }

    /// A rule recording every guide title matching `pattern` (a regex, ignoring case) on any channel.
    func createRegexRecordingRule(_ pattern: String) async throws {
        try await sendRaw("POST", "/api/live/recording-rules",
                          jsonObject: ["profileId": profileID, "matchType": "regex", "pattern": pattern,
                                       "allChannels": true])
    }

    /// Pauses / resumes a rule, switches it to new episodes only (or back), or changes its padding.
    func updateRecordingRule(_ id: String, enabled: Bool? = nil, newOnly: Bool? = nil, paddingBefore: Int? = nil,
                             paddingAfter: Int? = nil) async throws {
        var body: [String: Any] = ["profileId": profileID]
        if let enabled { body["enabled"] = enabled }
        if let newOnly { body["newOnly"] = newOnly }
        if let paddingBefore { body["paddingBeforeSeconds"] = paddingBefore }
        if let paddingAfter { body["paddingAfterSeconds"] = paddingAfter }
        try await sendRaw("PUT", "/api/live/recording-rules/\(Self.segment(id))", jsonObject: body)
    }

    /// Deletes a rule; the server cancels the upcoming recordings it scheduled.
    func deleteRecordingRule(_ id: String) async throws {
        try await sendRaw("DELETE", "/api/live/recording-rules/\(Self.segment(id))")
    }

    func recordingSettings() async throws -> RecordingSettings {
        try await send("GET", "/api/live/recording-settings", query: ["profileId": profileID])
    }

    func saveRecordingSettings(_ settings: RecordingSettings) async throws {
        try await sendRaw("PUT", "/api/live/recording-settings",
                          jsonObject: ["profileId": profileID,
                                       "paddingBeforeSeconds": settings.paddingBeforeSeconds,
                                       "paddingAfterSeconds": settings.paddingAfterSeconds])
    }
}
