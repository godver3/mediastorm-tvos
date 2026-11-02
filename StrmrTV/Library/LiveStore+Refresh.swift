import Foundation

/// More ▸ Refresh Guide & Channels: a forced re-download of the channel lineups and the guide.
extension LiveStore {
    /// Clears the server's channel caches and reloads the list. With the EPG on, the server
    /// also re-downloads its guide; once that is done, the guide data shown here is fetched
    /// again and swapped in, so the guide doesn't blank while it waits.
    func refresh() async {
        guideRefresh?.cancel()
        _ = try? await api.sendRaw("POST", "/api/live/cache/clear")
        let guide = epgEnabled == true
        var before: EPGStatus?
        if guide {
            before = try? await api.epgStatus()
            show(notice: String(localized: "Refreshing the guide…"), clearing: false)
            if (try? await api.sendRaw("POST", "/api/live/epg/refresh")) == nil {
                show(notice: String(localized: "Couldn't start a guide refresh."))
                before = nil
            }
        }
        nowNext = [:]
        nowNextFetched = [:]
        await reload(force: true)
        guard guide else {
            show(notice: String(localized: "Channels refreshed."))
            return
        }
        guard let before else { return }
        guideRefresh = Task { [weak self] in await self?.awaitGuideRefresh(after: before) }
    }

    /// Polls the guide status until the server's refresh finishes (ten minutes at most), then
    /// re-fetches the loaded guide data.
    private func awaitGuideRefresh(after before: EPGStatus) async {
        var sawRefreshing = before.refreshing == true
        let started = Date()
        var status: EPGStatus?
        while Date().timeIntervalSince(started) < 600 {
            try? await Task.sleep(for: .seconds(3))
            if Task.isCancelled { return }
            guard let current = try? await api.epgStatus() else { continue }
            status = current
            if current.refreshing == true { sawRefreshing = true; continue }
            // Done once a run was seen or a new guide landed; a run too quick to see (or one
            // that never started) counts as done after a few polls.
            if sawRefreshing || current.lastRefresh != before.lastRefresh || Date().timeIntervalSince(started) > 12 { break }
        }
        if Task.isCancelled { return }
        await refetchGuideData()
        if let error = status?.lastError, !error.isEmpty, status?.lastRefresh == before.lastRefresh {
            show(notice: String(localized: "Guide refresh failed: \(error)"))
        } else {
            show(notice: String(localized: "Guide refreshed."))
        }
    }

    /// Fetches every loaded guide chunk and now / next again, replacing what was there.
    func refetchGuideData() async {
        var keysByChunk: [Int: [String]] = [:]
        for entry in chunksLoaded {
            guard let bar = entry.firstIndex(of: "|"), let index = Int(entry[..<bar]) else { continue }
            keysByChunk[index, default: []].append(String(entry[entry.index(after: bar)...]))
        }
        var fresh: [String: [EPGProgram]] = [:]
        var failed = Set<String>()
        for (index, keys) in keysByChunk.sorted(by: { $0.key < $1.key }) {
            for batch in stride(from: 0, to: keys.count, by: 40).map({ Array(keys[$0..<min($0 + 40, keys.count)]) }) {
                if Task.isCancelled { return }
                guard let result = await chunkPrograms(index, keys: batch) else {
                    failed.formUnion(batch)
                    continue
                }
                for key in batch { fresh[key] = Self.merge(fresh[key] ?? [], result[key] ?? []) }
            }
        }
        var merged = schedules
        // Keys with a failed chunk keep their old programmes rather than losing part of the day.
        for (key, programs) in fresh where !failed.contains(key) { merged[key] = programs }
        schedules = merged

        let keys = Array(nowNext.keys)
        for batch in stride(from: 0, to: keys.count, by: 50).map({ Array(keys[$0..<min($0 + 50, keys.count)]) }) {
            guard let entries = try? await api.epgNow(batch) else { continue }
            for entry in entries {
                nowNext[entry.channelId] = entry
                nowNextFetched[entry.channelId] = Date()
            }
        }
    }
}
