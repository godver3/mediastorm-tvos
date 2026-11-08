import Foundation

/// Where a Stremio channel's stream lookup stands in the sports stream picker.
enum SportsStreamLookup: Equatable {
    case pending
    case loaded([LiveStremioStream])
    case failed
}

/// One row of the sports stream picker: a channel, or one stream of a Stremio channel.
struct SportsStreamRow: Identifiable, Hashable {
    let match: SportsStreamMatch
    /// The channel's streams are still being looked up ("Loading streams…").
    var loading = false
    /// The channel row's id, kept by its first stream once it expands (focus stays put).
    var id: String

    init(match: SportsStreamMatch, loading: Bool = false, id: String? = nil) {
        self.match = match
        self.loading = loading
        self.id = id ?? match.id
    }
}

/// What the picker does about a single strong match of a live event.
enum SportsStreamAutoPlay: Equatable {
    /// Show the list and let the user pick.
    case none
    /// The channel's streams are still being looked up.
    case wait
    case play(SportsStreamMatch)
}

/// The stream picker's rows (Expo `sports-stream-options.ts` `renderOptions`): a Stremio
/// channel whose streams have been looked up becomes one row per stream, in the addon's order,
/// titled "<channel> · <stream>" and keeping the match's source, confidence and badge; picking
/// one tunes that `stremioStreamIndex`. A lookup that is running shows the plain row as
/// loading; one that failed or found nothing leaves the plain row (the server picks).
enum SportsStreamOptions {
    /// At most this many lookups run at once.
    static let concurrency = 4
    /// Each lookup's allowance (Expo's 25 s); a lookup that runs over counts as failed.
    static let lookupTimeout: TimeInterval = 25

    /// The stream's label, title or name, else "Feed N".
    static func label(_ stream: LiveStremioStream) -> String {
        for text in [stream.label, stream.title, stream.name] {
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return String(localized: "Feed \(stream.index + 1)")
    }

    /// The URLs to look up: every distinct Stremio channel among the matches, in order.
    static func lookupURLs(_ matches: [SportsStreamMatch]) -> [String] {
        var seen = Set<String>()
        return matches.filter { $0.channel.hasStremioSources && seen.insert($0.channelUrl).inserted }.map(\.channelUrl)
    }

    /// The streams of a lookup with a usable, unique index, in the addon's order.
    static func streams(_ lookup: SportsStreamLookup?) -> [LiveStremioStream]? {
        guard case let .loaded(streams) = lookup else { return nil }
        var seen = Set<Int>()
        return streams.filter { $0.index >= 0 && seen.insert($0.index).inserted }
    }

    /// The match as one of its channel's streams.
    static func match(_ match: SportsStreamMatch, stream: LiveStremioStream) -> SportsStreamMatch {
        var picked = match
        picked.stremioStreamIndex = stream.index
        picked.streamLabel = label(stream)
        return picked
    }

    /// The rows for `matches` given the lookups so far (keyed by channel URL), without
    /// repeats of the same source, URL and stream.
    static func rows(_ matches: [SportsStreamMatch], lookups: [String: SportsStreamLookup]) -> [SportsStreamRow] {
        let rows = matches.flatMap { match -> [SportsStreamRow] in
            guard match.channel.hasStremioSources else { return [SportsStreamRow(match: match)] }
            let lookup = lookups[match.channelUrl]
            if let streams = streams(lookup), !streams.isEmpty {
                return streams.enumerated().map { offset, stream in
                    SportsStreamRow(match: Self.match(match, stream: stream), id: offset == 0 ? match.id : nil)
                }
            }
            return [SportsStreamRow(match: match, loading: lookup == nil || lookup == .pending)]
        }
        var seen = Set<String>()
        return rows.filter { seen.insert(identity($0.match)).inserted }
    }

    /// Rows are the same stream when source, URL and stream index are.
    static func identity(_ match: SportsStreamMatch) -> String {
        "\(match.sourceId ?? "")|\(match.channelUrl)|\(match.stremioStreamIndex.map(String.init) ?? "channel")"
    }

    /// One clear answer for an event in progress (a single strong match with no alternatives, on
    /// the first search): play it at once. A Stremio channel waits for its lookup and plays only
    /// when it lists exactly one stream (that one) or the lookup fails or finds none (the server
    /// picks); with several streams the list shows.
    static func autoPlay(live: Bool, broad: Bool, groups: [SportsStreamGroup],
                         lookups: [String: SportsStreamLookup]) -> SportsStreamAutoPlay {
        guard live, !broad, groups.count == 1, groups[0].confidenceTier == "strong",
              groups[0].alternatives?.isEmpty ?? true else { return .none }
        let primary = groups[0].primary
        guard primary.channel.hasStremioSources else { return .play(primary) }
        switch lookups[primary.channelUrl] {
        case nil, .pending: return .wait
        case .failed: return .play(primary)
        case .loaded:
            let found = streams(lookups[primary.channelUrl]) ?? []
            if found.isEmpty { return .play(primary) }
            return found.count == 1 ? .play(match(primary, stream: found[0])) : .none
        }
    }
}
