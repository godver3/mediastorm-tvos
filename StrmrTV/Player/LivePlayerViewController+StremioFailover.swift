import Foundation

/// Which stream of a Stremio channel to try next, as Expo's `nextUntriedStremioStreamIndex`:
/// the first playable stream, in the addon's order, not tried yet in this player.
struct StremioFailover {
    /// The playable streams' indexes; nil until the server or the stream list has said.
    private(set) var available: [Int]?
    private(set) var tried: Set<Int> = []

    /// A tune of `index` (nil: the server picked, which is the first playable stream).
    mutating func noteTuned(index: Int?, available indexes: [Int]?) {
        if let indexes, !indexes.isEmpty { available = indexes }
        if let index { tried.insert(index) } else if tried.isEmpty, let first = available?.first { tried.insert(first) }
    }

    mutating func learn(available indexes: [Int]) {
        available = indexes
        if tried.isEmpty, let first = indexes.first { tried.insert(first) }
    }

    /// The next untried stream, marked tried; nil when every one has been.
    mutating func next() -> Int? {
        guard let index = available?.first(where: { !tried.contains($0) }) else { return nil }
        tried.insert(index)
        return index
    }
}

/// Stremio failover, as the Expo player's live recovery does it. A Stremio addon channel
/// lists several streams of the same broadcast (sports addons especially); when the one
/// playing fails for good (an error the direct → HLS fallback can't fix, a start the server
/// rejects, or retunes used up) the channel is tuned again on the next stream it hasn't
/// tried, with "Trying another stream source…" on the loading cover. Only when every stream
/// has been tried does the player close with the error. The playable streams come from the
/// HLS session's `stremioStreamIndexes`, or for a direct stream from the addon's list
/// (`GET /api/live/stremio/streams`), fetched on the first failure.
extension LivePlayerViewController {
    /// Fails the channel, unless it is a Stremio channel with a stream left to try.
    func failOrFailOver(_ message: String) {
        guard !didFinish else { return }
        guard channel.hasStremioSources, failoverTask == nil else {
            if failoverTask == nil { fail(message) }
            return
        }
        failoverTask = Task { [weak self] in
            guard let self else { return }
            defer { failoverTask = nil }
            if stremioFailover.available == nil {
                do {
                    let streams = try await api.liveStremioStreams(channel)
                    stremioFailover.learn(available: streams.map(\.index))
                } catch {
                    log.error("stremio failover: stream list failed (\(error.localizedDescription))")
                }
            }
            guard !Task.isCancelled, !didFinish else { return }
            guard let index = stremioFailover.next() else {
                log.notice("stremio failover: no untried streams left")
                fail(message)
                return
            }
            log.notice("stremio failover: stream \(index) after \(message)")
            channel.stremioStreamIndex = index
            // A new stream gets the full retune budget.
            retuneCount = 0
            cover.show(note: String(localized: "Trying another stream source…"))
            // Close the failed stream's provider connection before the next one opens.
            engine.stop()
            tune(after: 0.3)
        }
    }
}
