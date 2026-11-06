import Foundation

extension APIClient {
    /// The profile's recordings, every status (`GET /api/live/recordings`).
    func recordings() async throws -> [Recording] {
        let response: RecordingsResponse = try await send("GET", "/api/live/recordings", query: ["profileId": profileID])
        return response.recordings ?? []
    }

    /// Cancels a scheduled recording or stops one in progress (what was captured is kept).
    func cancelRecording(_ id: String) async throws {
        try await sendRaw("POST", "/api/live/recordings/\(Self.segment(id))/cancel")
    }

    /// Deletes the recording and its file.
    func deleteRecording(_ id: String) async throws {
        try await sendRaw("DELETE", "/api/live/recordings/\(Self.segment(id))")
    }

    /// The recording's file (`/api/live/recordings/{id}/stream`), as the Expo player opens it: the
    /// metadata names the stream on the admin dashboard; `token=` / `profileUnlock=` ride in the
    /// query as on every header-less media URL. Finished recordings play this.
    func recordingStreamURL(_ recording: Recording) -> URL {
        var query = ["profileId": profileID, "mediaType": "channel", "title": recording.displayTitle]
        if let profileName, !profileName.isEmpty { query["profileName"] = profileName }
        let itemID = (recording.tvgId ?? "").isEmpty ? recording.channelId : recording.tvgId ?? ""
        if !itemID.isEmpty { query["itemId"] = itemID }
        if let token { query["token"] = token }
        if let unlock = profileUnlocks.token(for: profileID) { query["profileUnlock"] = unlock }
        return url("/api/live/recordings/\(Self.segment(recording.id))/stream", query: query)
    }

    /// A recording still being written, as an HLS session over the growing file: an EVENT playlist
    /// listing every segment from the start, which gains segments as the recording grows and an
    /// ENDLIST about 20 s after its last write. Stop it with `stopLiveSession`.
    func startRecordingHLS(_ recording: Recording) async throws -> (url: URL, sessionID: String) {
        let file = (recording.outputPath ?? "").split(separator: "/").last.map(String.init) ?? "recording.ts"
        var q = ["path": "recording:\(recording.id)/\(file)", "profileId": profileID, "title": recording.displayTitle]
        if let profileName, !profileName.isEmpty { q["profileName"] = profileName }
        let start: RecordingHLSStart = try await send("GET", "/api/video/hls/start", query: q, timeout: 60)
        guard let path = start.playlistUrl, !path.isEmpty, let sessionID = start.sessionId else {
            throw APIError.notReady("The server did not return a playlist for this recording")
        }
        return (try mediaURL(apiPath: path), sessionID)
    }

    /// Keeps a recording's HLS session alive and reports where playback is. Returns whether the
    /// server still follows the growing file (nil when the call failed).
    func keepRecordingHLSAlive(_ sessionID: String, time: Double, paused: Bool, buffering: Bool) async -> Bool? {
        let q = ["time": String(format: "%.1f", time), "paused": String(paused), "buffering": String(buffering)]
        guard let data = try? await sendRaw("POST", "/api/video/hls/\(Self.segment(sessionID))/keepalive", query: q,
                                            promptOnLock: false, timeout: 10),
              let reply = try? decoder.decode(RecordingHLSKeepAlive.self, from: data) else { return nil }
        return reply.growing ?? false
    }
}

// MARK: Scheduling (the Expo Live guide's programme and channel menus)

extension APIClient {
    /// Scheduled, starting and recording ones: what the guide marks (`status=pending,starting,running`).
    func activeRecordings() async throws -> [Recording] {
        let response: RecordingsResponse = try await send(
            "GET", "/api/live/recordings", query: ["profileId": profileID, "status": "pending,starting,running"],
            promptOnLock: false)
        return response.recordings ?? []
    }

    /// Records one programme (`POST /api/live/recordings/epg`); the server adds the profile's padding.
    func recordProgram(_ program: EPGProgram, on channel: LiveChannel) async throws {
        try await sendRaw("POST", "/api/live/recordings/epg",
                          jsonObject: Self.recordingBody(channel, title: program.title, description: program.description,
                                                         start: program.start, stop: program.stop, profileID: profileID))
    }

    /// Records the channel from now for `duration` (`POST /api/live/recordings/time-block`).
    func recordTimeBlock(_ channel: LiveChannel, duration: TimeInterval) async throws {
        let start = Date()
        try await sendRaw("POST", "/api/live/recordings/time-block",
                          jsonObject: Self.recordingBody(channel, title: "\(channel.name) Live Block",
                                                         description: "Scheduled from the Live TV action menu.",
                                                         start: start, stop: start.addingTimeInterval(duration),
                                                         profileID: profileID))
    }

    /// Records every airing of `title` on this channel: a title rule scoped to the channel, so +1 /
    /// simulcast channels don't record it twice (Expo's Record Series).
    func recordSeries(_ title: String, on channel: LiveChannel, newOnly: Bool = false) async throws {
        var body: [String: Any] = ["profileId": profileID, "matchType": "title", "pattern": title,
                                   "channelId": channel.id, "channelName": channel.name, "newOnly": newOnly]
        if let tvg = channel.tvgId, !tvg.isEmpty { body["tvgId"] = tvg }
        try await sendRaw("POST", "/api/live/recording-rules", jsonObject: body)
    }

    private static func recordingBody(_ channel: LiveChannel, title: String, description: String?,
                                      start: Date, stop: Date, profileID: String) -> [String: Any] {
        let format = Date.ISO8601FormatStyle()
        var body: [String: Any] = ["profileId": profileID, "channelId": channel.id, "channelName": channel.name,
                                   "title": title, "sourceUrl": channel.url,
                                   "start": start.formatted(format), "stop": stop.formatted(format)]
        if let tvg = channel.tvgId, !tvg.isEmpty { body["tvgId"] = tvg }
        if let description, !description.isEmpty { body["description"] = description }
        return body
    }
}
