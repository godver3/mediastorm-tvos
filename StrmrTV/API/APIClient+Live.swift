import Foundation

extension APIClient {
    /// One page of channels. The server filters by category / search and keeps favorites
    /// (`favoriteIds`) first and through every filter; hidden channels are dropped here.
    func liveChannels(sourceID: String?, categories: [String], favoritesOnly: Bool, search: String,
                      favoriteIDs: [String], offset: Int, limit: Int) async throws -> LiveChannelsPage {
        var body: [String: Any] = [
            "profileId": profileID, "offset": offset, "limit": limit,
            "favoriteIds": favoriteIDs, "favoritesOnly": favoritesOnly,
        ]
        if let sourceID { body["sourceId"] = sourceID }
        if !categories.isEmpty { body["categories"] = categories }
        if !search.isEmpty { body["filter"] = search }
        return try await send("POST", "/api/live/channels", jsonObject: body, timeout: 60)
    }

    func epgStatus() async throws -> EPGStatus {
        try await send("GET", "/api/live/epg/status", query: ["profileId": profileID])
    }

    /// Now / next for up to 50 EPG keys.
    func epgNow(_ keys: [String]) async throws -> [EPGNowPlaying] {
        try await send("POST", "/api/live/epg/now", query: ["profileId": profileID], jsonObject: ["channels": keys])
    }

    /// Programmes overlapping `[now + startOffset, + hours]` for each key (every key is in the
    /// answer, with `null` when it has none).
    func epgSchedule(_ keys: [String], startOffsetMinutes: Int, hours: Int) async throws -> [String: [EPGProgram]] {
        let raw: [String: [EPGProgram]?] = try await send("GET", "/api/live/epg/schedule/batch", query: [
            "channels": keys.joined(separator: ","), "hours": String(hours),
            "startOffset": String(startOffsetMinutes), "profileId": profileID,
        ])
        return raw.mapValues { $0 ?? [] }
    }

    /// The profile's `liveTV` favorites and hidden channels, from user settings.
    func liveChannelLists() async throws -> (favorites: [String], hidden: [String]) {
        let live = try await userSettingsObject()["liveTV"] as? [String: Any]
        return (live?["favoriteChannels"] as? [String] ?? [], live?["hiddenChannels"] as? [String] ?? [])
    }

    /// Writes favorites / hidden channels. The settings PUT replaces the whole document, so
    /// it is re-read and only these keys change (as the Expo app does).
    func saveLiveChannelLists(favorites: [String], hidden: [String]) async throws {
        var settings = try await userSettingsObject()
        var live = settings["liveTV"] as? [String: Any] ?? [:]
        live["favoriteChannels"] = favorites
        live["hiddenChannels"] = hidden
        settings["liveTV"] = live
        try await sendRaw("PUT", "\(profilePath)/settings", jsonObject: settings)
    }

    private func userSettingsObject() async throws -> [String: Any] {
        let data = try await sendRaw("GET", "\(profilePath)/settings")
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Opens a channel on the server and returns the URL the engine plays: a direct stream,
    /// or an HLS session (`sessionID`, kept alive with `keepLiveSessionAlive`).
    /// `token=` / `profileUnlock=` ride in the query as on every header-less media URL.
    /// `forceHLS`: an HLS session even when the source is set to direct (`format=hls`).
    func startLive(_ channel: LiveChannel, programTitle: String?,
                   forceHLS: Bool = false) async throws -> (url: URL, sessionID: String?) {
        var query = liveStartQuery(channel, programTitle: programTitle)
        if forceHLS { query["format"] = "hls" }
        let start: LiveStart = try await send("GET", "/api/live/hls/start", query: query, timeout: 60)
        let isDirect = start.isDirect == true
        guard let path = isDirect ? start.streamUrl : start.playlistUrl, !path.isEmpty else {
            throw APIError.notReady("The server did not return a stream for this channel")
        }
        return (try mediaURL(apiPath: path), isDirect ? nil : start.sessionId)
    }

    /// The `/api/live/hls/start` query for `channel`.
    func liveStartQuery(_ channel: LiveChannel, programTitle: String?) -> [String: String] {
        var q = [
            "url": channel.url, "target": "native", "profileId": profileID,
            "mediaType": "channel", "title": programTitle ?? channel.name,
            "channelId": channel.playbackId ?? channel.id, "channelName": channel.name,
            "liveSourceUrl": channel.url,
        ]
        if let profileName, !profileName.isEmpty { q["profileName"] = profileName }
        if let v = channel.sourceId { q["sourceId"] = v; q["liveSourceId"] = v }
        if let v = channel.tvgId { q["itemId"] = v }
        if let v = channel.tvgName { q["tvgName"] = v }
        if let v = channel.group { q["category"] = v }
        if let v = channel.logo { q["liveChannelLogo"] = v }
        if let v = channel.stremioStreamIndex, v >= 0 { q["stremioStreamIndex"] = String(v) }
        return q
    }

    /// The streams a Stremio channel's addon lists for it, for Choose Source.
    func liveStremioStreams(_ channel: LiveChannel) async throws -> [LiveStremioStream] {
        struct Response: Decodable { let streams: [LiveStremioStream]? }
        let response: Response = try await send("GET", "/api/live/stremio/streams",
                                                query: ["url": channel.url, "profileId": profileID], timeout: 60)
        return response.streams ?? []
    }

    /// The server's stable remote-access identity, which Live TV's remembered HLS choice is
    /// kept under (`LiveHLSPreference`).
    func serverIdentity() async throws -> String? {
        struct Identity: Decodable { let serverId: String? }
        let identity: Identity = try await send("GET", "/api/remote-access/identity", promptOnLock: false, timeout: 5)
        return identity.serverId
    }

    func keepLiveSessionAlive(_ sessionID: String) async {
        _ = try? await sendRaw("POST", "/api/video/hls/\(Self.segment(sessionID))/keepalive", promptOnLock: false, timeout: 10)
    }

    func stopLiveSession(_ sessionID: String) async {
        _ = try? await sendRaw("POST", "/api/video/hls/\(Self.segment(sessionID))/stop", promptOnLock: false, timeout: 10)
    }

    /// A server-relative media path (`/live/stream?…`, `/video/hls/…`) under `/api`, with the
    /// session token and profile unlock added to its query.
    func mediaURL(apiPath: String) throws -> URL {
        let parts = apiPath.split(separator: "?", maxSplits: 1).map(String.init)
        var extra: [String] = []
        if let token { extra.append("token=\(Self.segment(token))") }
        if let unlock = profileUnlocks.token(for: profileID) { extra.append("profileUnlock=\(Self.segment(unlock))") }
        let query = ([parts.count > 1 ? parts[1] : nil] + extra).compactMap { $0 }.filter { !$0.isEmpty }
        return url("/api" + parts[0], encodedQuery: query.joined(separator: "&"))
    }
}
