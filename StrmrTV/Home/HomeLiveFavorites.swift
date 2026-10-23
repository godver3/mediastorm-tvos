import Foundation

/// The Favorite Channels row (`live-favorites`), as the Expo Home builds it: the profile's
/// favorite channels minus hidden ones, in favorites order, each showing what is on now when
/// the server has guide data. Select tunes the channel in the live player.
extension APIClient {
    func favoriteChannelCards(limit: Int) async throws -> [HomeCard] {
        let lists = try await liveChannelLists()
        let hidden = Set(lists.hidden)
        let favorites = lists.favorites.filter { !hidden.contains($0) }
        guard !favorites.isEmpty else { return [] }
        let page = try await liveChannels(sourceID: nil, categories: [], favoritesOnly: true, search: "",
                                          favoriteIDs: favorites, offset: 0, limit: max(limit, favorites.count))
        let order = Dictionary(favorites.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let channels = page.channels
            .filter { order[$0.id] != nil && !hidden.contains($0.id) }
            .sorted { order[$0.id]! < order[$1.id]! }
            .prefix(limit)

        // Now playing, when the guide is on; a guide failure just leaves channel names.
        var now: [String: EPGProgram] = [:]
        if (try? await epgStatus())?.enabled == true {
            let keys = channels.map(\.guideKey)
            for start in stride(from: 0, to: keys.count, by: 50) {
                let batch = Array(keys[start..<min(start + 50, keys.count)])
                for entry in (try? await epgNow(batch)) ?? [] { now[entry.channelId] = entry.current }
            }
        }
        return channels.map { HomeCard(channel: $0, program: now[$0.guideKey]) }
    }
}

extension HomeCard {
    init(channel: LiveChannel, program: EPGProgram?) {
        let airing = program.flatMap { $0.isAiring(at: Date()) ? $0 : nil }
        self.init(id: "live-channel:\(channel.id)", link: .channel(channel, program: airing),
                  title: airing?.title ?? channel.name,
                  subtitle: airing != nil ? channel.name : channel.group ?? String(localized: "Live TV"),
                  overview: airing?.description,
                  backdropURL: airing?.icon,
                  // No programme art: the channel logo on a plain tile.
                  logoURL: channel.logoURL?.absoluteString, logoTile: airing?.icon == nil)
    }
}
