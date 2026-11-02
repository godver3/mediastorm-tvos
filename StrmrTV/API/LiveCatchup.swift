import Foundation

/// The provider's catch-up for a channel (`LiveChannel.catchup`): it keeps `days` of past
/// programmes and replays them on request. Nothing is recorded; the server only turns a guide
/// programme into the provider's archive URL (`GET /api/live/catchup`).
struct LiveCatchup: Codable, Hashable {
    let days: Int
    let mode: String?
}

/// `GET /api/live/catchup`: the provider URL to tune for a programme, from `offsetSeconds` in
/// (the provider may round down to a whole minute), running `durationSeconds`.
struct LiveCatchupStart: Decodable {
    let url: String
    let offsetSeconds: Int
    let durationSeconds: Int
}

extension LiveChannel {
    /// How far back the provider replays this channel; nil without catch-up.
    var catchupWindow: TimeInterval? {
        guard let days = catchup?.days, days > 0 else { return nil }
        return TimeInterval(days) * 86_400
    }

    /// The provider can replay `program` from its start: it has started and is in the archive.
    func canReplay(_ program: EPGProgram?, now: Date = Date()) -> Bool {
        guard let program, let window = catchupWindow else { return false }
        return program.start < now.addingTimeInterval(-60) && program.start >= now.addingTimeInterval(-window)
    }
}

extension LiveStore {
    /// How far back the guide pages: the longest archive among the channels shown (capped at
    /// a week, the server's default EPG retention), else the half hour it always kept.
    var guideHistory: TimeInterval {
        let window = visibleChannels.lazy.compactMap(\.catchupWindow).max() ?? 0
        return min(max(window, 1800), 7 * 86_400)
    }
}

extension APIClient {
    /// The provider's archive URL for `program` on `channel`, from `offset` seconds in.
    func liveCatchup(_ channel: LiveChannel, program: EPGProgram, offset: Int) async throws -> LiveCatchupStart {
        var query = ["channelId": channel.id, "profileId": profileID,
                     "start": program.start.ISO8601Format(), "stop": program.stop.ISO8601Format(),
                     "offset": String(max(0, offset))]
        if let v = channel.sourceId { query["sourceId"] = v }
        return try await send("GET", "/api/live/catchup", query: query, timeout: 30)
    }

    /// The archive as a file through the server's stream proxy: the provider serves it with a
    /// length and byte ranges (an Xtream timeshift is a whole TS file), so it seeks as VOD.
    func catchupStreamURL(_ archive: LiveCatchupStart, channel: LiveChannel, program: EPGProgram) -> URL {
        streamURL(for: archive.url, metadata: ["mediaType": "channel", "title": program.title,
                                               "channelName": channel.name])
    }
}
