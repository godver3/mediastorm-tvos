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

/// The live channels that look like they carry a game or race session
/// (`/api/sports/game/{id}/streams`), strongest match first. Picking one closes the list and
/// tunes it in the Live TV player; a single strong match of a live event plays at once.
/// "Search All Sources" widens the search past the admin's default sources for the league.
struct SportsStreamPicker: View {
    let target: SportsWatchTarget
    /// Called with the pick; the presenter closes the list and tunes it once it is gone.
    let onPick: (SportsStreamMatch) -> Void

    @State private var matches: [SportsStreamMatch] = []
    @State private var loading = true
    @State private var broad = false
    @State private var error: String?

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
                if loading {
                    HStack(spacing: 24) {
                        ProgressView()
                        Text(broad ? "Searching all sources…" : "Searching channels…").foregroundStyle(.secondary)
                    }
                } else {
                    if let error { Text(error).foregroundStyle(.secondary) }
                    ForEach(matches) { match in
                        Button { play(match) } label: { row(match) }
                            .accessibilityIdentifier("sports-stream-\(match.channelId)")
                    }
                    if !broad {
                        Button { Task { await search(broad: true) } } label: {
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
        .task { await search(broad: false) }
    }

    private var subtitle: String {
        if loading { return String(localized: "Looking for live channels") }
        return matches.count == 1 ? String(localized: "1 channel") : String(localized: "\(matches.count) channels")
    }

    private func row(_ match: SportsStreamMatch) -> some View {
        HStack(spacing: 28) {
            RemoteImage(url: match.channel.logoURL, size: CGSize(width: 120, height: 68), contentMode: .fit) { _ in
                Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
            }
            .frame(width: 120, height: 68)
            VStack(alignment: .leading, spacing: 6) {
                Text(match.channelName).font(.headline).lineLimit(1)
                Text(details(match)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(match.isStrong ? "Strong match" : "Possible match")
                .font(.caption.weight(.semibold))
                .foregroundStyle(match.isStrong ? Color.green : .secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func details(_ match: SportsStreamMatch) -> String {
        let percent = match.confidence.map { "\(Int(($0 * 100).rounded()))%" }
        return [match.sourceName, match.programTitle, match.matchReason, percent]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    private func search(broad: Bool) async {
        self.broad = broad
        loading = true
        defer { loading = false }
        do {
            let groups = try await APIClient.shared.sportsStreams(target.id, broad: broad, kind: target.kind,
                                                                     parentId: target.parentID)
                .filter { ($0.confidenceTier == "strong" || $0.confidenceTier == "possible") && !$0.primary.channelUrl.isEmpty }
            var seen = Set<String>()
            let feeds: [SportsStreamMatch] = groups.flatMap { [$0.primary] + ($0.alternatives ?? []) }
                .filter { !$0.channelUrl.isEmpty && seen.insert($0.id).inserted }
            // Strong matches first, otherwise in the server's order.
            matches = feeds.filter(\.isStrong) + feeds.filter { !$0.isStrong }
            error = matches.isEmpty ? String(localized: "No channel looks like it carries this \(target.noun).") : nil
            // One clear answer for a game in progress: no need to ask.
            if !broad, target.live, groups.count == 1, groups[0].confidenceTier == "strong",
               groups[0].alternatives?.isEmpty ?? true {
                play(groups[0].primary)
            }
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
        }
    }

    private func play(_ match: SportsStreamMatch) {
        onPick(match)
    }
}
