import SwiftUI

/// What the stream picker looks for: a game, or a race session with its weekend (`kind`
/// `racing`, `parentId`; Expo `raceWatchTarget`).
struct SportsWatchTarget {
    let id: String
    let title: String
    let live: Bool
    var kind: String?
    var parentID: String?
    /// What to say when nothing matches.
    var noun = String(localized: "game")

    init(id: String, title: String, live: Bool, kind: String? = nil, parentID: String? = nil, noun: String? = nil) {
        self.id = id
        self.title = title
        self.live = live
        self.kind = kind
        self.parentID = parentID
        if let noun { self.noun = noun }
    }

    init(game: SportsGame) {
        self.init(id: game.id, title: game.displayTitle, live: game.lifecycle == .live)
    }
}

/// The stream search behind the TV and phone pickers: the server's strong and possible matches
/// for a target (`/api/sports/game/{id}/streams`), each group's primary and alternatives without
/// repeats, strong matches first, otherwise in the server's order.
enum SportsStreamSearch {
    @MainActor
    static func find(_ target: SportsWatchTarget, broad: Bool) async throws
        -> (matches: [SportsStreamMatch], groups: [SportsStreamGroup]) {
        let groups = try await APIClient.shared.sportsStreams(target.id, broad: broad, kind: target.kind,
                                                                 parentId: target.parentID)
            .filter { ($0.confidenceTier == "strong" || $0.confidenceTier == "possible") && !$0.primary.channelUrl.isEmpty }
        var seen = Set<String>()
        let feeds: [SportsStreamMatch] = groups.flatMap { [$0.primary] + ($0.alternatives ?? []) }
            .filter { !$0.channelUrl.isEmpty && seen.insert($0.id).inserted }
        return (feeds.filter(\.isStrong) + feeds.filter { !$0.isStrong }, groups)
    }

    static func emptyMessage(_ target: SportsWatchTarget) -> String {
        String(localized: "No channel looks like it carries this \(target.noun).")
    }

    /// "Source · Program · Reason · 92%", with the channel after the source on a stream row
    /// (its headline is the stream, `rowTitle`).
    static func details(_ match: SportsStreamMatch) -> String {
        let percent = match.confidence.map { "\(Int(($0 * 100).rounded()))%" }
        let channel = match.streamLabel == nil ? nil : match.channelName
        return [match.sourceName, channel, match.programTitle, match.matchReason, percent]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

/// The live channels that look like they carry a game or race session
/// (`/api/sports/game/{id}/streams`), strongest match first. Picking one closes the list and
/// tunes it in the Live TV player; a single strong match of a live event plays at once. A Stremio
/// addon channel lists its streams as rows of their own once looked up (`SportsStreamOptions`).
/// "Search All Sources" widens the search past the admin's default sources for the league.
struct SportsStreamPicker: View {
    let target: SportsWatchTarget
    /// Called with the pick; the presenter closes the list and tunes it once it is gone.
    let onPick: (SportsStreamMatch) -> Void

    @State private var matches: [SportsStreamMatch] = []
    @State private var groups: [SportsStreamGroup] = []
    @State private var loading = true
    @State private var broad = false
    @State private var error: String?
    /// A single strong match waits for its Stremio lookup before it plays by itself.
    @State private var autoPlayWaiting = false
    @StateObject private var lookups = SportsStreamLookups()

    private var rows: [SportsStreamRow] { SportsStreamOptions.rows(matches, lookups: lookups.states) }

    init(target: SportsWatchTarget, onPick: @escaping (SportsStreamMatch) -> Void) {
        self.target = target
        self.onPick = onPick
    }

    init(game: SportsGame, onPick: @escaping (SportsStreamMatch) -> Void) {
        self.init(target: SportsWatchTarget(game: game), onPick: onPick)
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(target.title).font(.title2.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
                if loading || waitingOnLookup {
                    HStack(spacing: 24) {
                        ProgressView()
                        Text(broad ? "Searching all sources…" : "Searching channels…").foregroundStyle(.secondary)
                    }
                } else {
                    if let error { Text(error).foregroundStyle(.secondary) }
                    ForEach(rows) { row in
                        Button { play(row.match) } label: { self.row(row) }
                            .accessibilityIdentifier("sports-stream-\(row.match.channelId)"
                                + (row.match.stremioStreamIndex.map { "-\($0)" } ?? ""))
                    }
                    if !broad {
                        Button { broad = true } label: {
                            Label("Search All Sources", systemImage: "magnifyingglass")
                        }
                        .padding(.top, 20)
                        .accessibilityIdentifier("sports-search-all")
                    }
                }
            }
            .padding(80)
        }
        .background { SourcePickerBackdrop(url: nil) }
        // A new search (Search All Sources) or the list going away cancels the one running and its lookups.
        .task(id: broad) {
            await search(broad: broad)
            await lookups.run(matches)
        }
        .onChange(of: lookups.states) { checkAutoPlay() }
    }

    private var subtitle: String {
        if loading || waitingOnLookup { return String(localized: "Looking for live channels") }
        let count = rows.count
        return count == 1 ? String(localized: "1 stream") : String(localized: "\(count) streams")
    }

    private func row(_ row: SportsStreamRow) -> some View {
        let match = row.match
        return HStack(spacing: 28) {
            RemoteImage(url: match.channel.logoURL, size: CGSize(width: 120, height: 68), contentMode: .fit) { _ in
                Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
            }
            .frame(width: 120, height: 68)
            VStack(alignment: .leading, spacing: 6) {
                Text(match.rowTitle).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                Text(row.loading ? [details(match), String(localized: "Loading streams…")].filter { !$0.isEmpty }
                        .joined(separator: " · ") : details(match))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(match.isStrong ? "Strong match" : "Possible match")
                .font(.caption.weight(.semibold))
                .foregroundStyle(match.isStrong ? Color.green : .secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ match: SportsStreamMatch) -> String { SportsStreamSearch.details(match) }

    private func search(broad: Bool) async {
        autoPlayWaiting = false
        loading = true
        defer { loading = false }
        do {
            let found = try await SportsStreamSearch.find(target, broad: broad)
            matches = found.matches
            error = matches.isEmpty ? SportsStreamSearch.emptyMessage(target) : nil
            self.groups = found.groups
            // One clear answer for a game in progress: no need to ask (a Stremio channel waits
            // for its streams).
            autoPlayWaiting = !broad
            checkAutoPlay()
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    /// The lone strong match of a live event is waiting on its Stremio lookup: the spinner stays.
    private var waitingOnLookup: Bool {
        autoPlayWaiting && SportsStreamOptions.autoPlay(live: target.live, broad: broad, groups: groups,
                                                         lookups: lookups.states) == .wait
    }

    private func checkAutoPlay() {
        guard autoPlayWaiting else { return }
        switch SportsStreamOptions.autoPlay(live: target.live, broad: broad, groups: groups, lookups: lookups.states) {
        case .wait: return
        case .none: autoPlayWaiting = false
        case let .play(match):
            autoPlayWaiting = false
            play(match)
        }
    }

    private func play(_ match: SportsStreamMatch) {
        autoPlayWaiting = false
        onPick(match)
    }
}
