#if os(iOS)
import SwiftUI

/// A game's page on a phone (Expo `app/sports/[eventId].tsx` with `SportsGameDetailTV`): the
/// scoreboard (`MobileSportsGameHeader`), Watch Live / Find Streams (the stream picker sheet),
/// Follow for each team, then the tabs the feed can fill (Overview, the sport's own, Box Score,
/// Play-by-Play, Standings) and the shown tab. Overviews and the sport-specific tabs are the TV's
/// panels (`SportsGameContent`), stacked into one column on a narrow screen; Box Score and
/// Standings are phone tables. With scores hidden there are no tabs. Refreshed every 30 s
/// while live, 60 s otherwise; pull to refresh.
struct MobileSportsGameView: View {
    let ref: SportsGameRef
    @ObservedObject var hub: SportsHubStore

    @ObservedObject private var spoilers = SportsSpoilers.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var game: SportsGame?
    @State private var error: String?
    @State private var followFailure: String?
    @State private var picking = false
    /// The stream picked, tuned once the sheet has gone (the player can't present over it).
    @State private var chosen: SportsStreamMatch?
    @State private var selectedTab: SportsGameTab = .overview
    @State private var playerTarget: SportsPlayerTarget?

    var body: some View {
        ScrollViewReader { proxy in
            MobileSportsScroll {
                VStack(alignment: .leading, spacing: 16) {
                    if let game {
                        content(SportsGamePage(game: game, league: hub.leagues[game.league]), proxy: proxy)
                    } else if let error {
                        ContentUnavailableView("Game Unavailable", systemImage: "sportscourt", description: Text(error))
                            .padding(.top, 60)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 120)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground))
        .environment(\.sportsStacksColumns, sizeClass == .compact)
        .navigationTitle(ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { spoilers.hidden.toggle() } label: {
                    Label(spoilers.hidden ? "Show Scores" : "Hide Scores", systemImage: spoilers.hidden ? "eye.slash" : "eye")
                }
                .accessibilityIdentifier("sports-detail-spoilers")
            }
        }
        .refreshable { await reload() }
        .onChange(of: selectedTab) { _, tab in
            if tab != .stats { playerTarget = nil }
        }
        .onChange(of: spoilers.hidden) { playerTarget = nil }
        .task(id: ref.id) { await refreshLoop() }
        .sheet(isPresented: $picking, onDismiss: tuneChosen) {
            if let game {
                MobileSportsStreamPicker(target: SportsWatchTarget(game: game)) { match in
                    chosen = match
                    picking = false
                }
            }
        }
    }

    @ViewBuilder private func content(_ page: SportsGamePage, proxy: ScrollViewProxy) -> some View {
        let tabs = SportsGameTab.available(for: page, spoilers: spoilers.hidden)
        let shown = SportsGameTab.shown(selectedTab, in: tabs)
        MobileSportsGameHeader(page: page, spoilers: spoilers.hidden)
        actions(page.game)
        if let followFailure {
            Text(followFailure).font(.footnote).foregroundStyle(.secondary)
                .task(id: followFailure) {
                    try? await Task.sleep(for: .seconds(4))
                    if !Task.isCancelled { self.followFailure = nil }
                }
        }
        if tabs.count > 1 {
            MobileSportsTabBar(tabs: tabs, label: { $0.label(page.kind) }, selection: Binding(get: { shown }, set: { selectedTab = $0 }))
                .id("sports-tabs")
        }
        Group {
            if spoilers.hidden {
                SportsSpoilerOverview(page: page)
            } else {
                tab(shown, page: page)
                    .environment(\.sportsShowPlayer, SportsPageAction { target in
                        playerTarget = target
                        selectedTab = .stats
                        withAnimation { proxy.scrollTo("sports-tabs", anchor: .top) }
                    })
                Text(SportsFormat.freshness(page, stale: page.isStale()))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func tab(_ tab: SportsGameTab, page: SportsGamePage) -> some View {
        switch tab {
        case .stats: MobileSportsBoxScore(page: page, target: playerTarget)
        case .standings: MobileSportsGameStandings(page: page)
        default: SportsGameContent(page: page, tab: tab, playerTarget: playerTarget)
        }
    }

    private func canWatch(_ game: SportsGame) -> Bool { [.live, .scheduled, .delayed].contains(game.lifecycle) }

    private func actions(_ game: SportsGame) -> some View {
        let follows = hub.preferences != nil && SportsTeamFollows.isTeamMatchup(game, kind: hub.kind(game))
        return HStack(spacing: 10) {
            if canWatch(game) {
                Button { picking = true } label: {
                    Label(game.lifecycle == .live ? "Watch Live" : "Find Streams", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(game.lifecycle == .live ? SportsStatusPill.live : .accentColor)
                .accessibilityIdentifier("sports-watch")
            }
            if follows {
                Menu {
                    ForEach([game.homeTeam, game.awayTeam], id: \.id) { team in
                        let followed = hub.isFollowed(team, in: game)
                        Button {
                            Task {
                                if let failure = await hub.setTeam(team, in: game, followed: !followed) { followFailure = failure }
                            }
                        } label: {
                            Label(followed ? "Unfollow \(team.name)" : "Follow \(team.name)",
                                  systemImage: followed ? "star.slash" : "star")
                        }
                        .accessibilityIdentifier("sports-follow-team-\(team.id)")
                    }
                } label: {
                    let any = [game.homeTeam, game.awayTeam].contains { hub.isFollowed($0, in: game) }
                    Label(any ? "Following" : "Follow", systemImage: any ? "star.fill" : "star")
                        .frame(maxWidth: canWatch(game) ? nil : .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(hub.savingTeams)
                .accessibilityIdentifier("sports-follow")
            }
        }
        .controlSize(.large)
    }

    private func tuneChosen() {
        guard let match = chosen else { return }
        chosen = nil
        LivePlayback.play(match.channel, program: nil)
    }

    private func reload() async {
        do {
            game = try await APIClient.shared.sportsGame(ref.id)
            error = nil
        } catch {
            if !(error is CancellationError), game == nil { self.error = error.localizedDescription }
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await reload()
            try? await Task.sleep(for: .seconds(game?.lifecycle == .live ? 30 : 60))
        }
    }
}

/// A page's tabs: a segmented control when the labels fit the width, else a row of chips that
/// scrolls sideways.
struct MobileSportsTabBar<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    let label: (Tab) -> String
    @Binding var selection: Tab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Section", selection: $selection) {
                ForEach(tabs) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .frame(maxWidth: .infinity)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        Button { selection = tab } label: {
                            MobileSportsChipLabel(title: label(tab), symbol: nil, on: tab == selection)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == selection ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("sports-tabs")
    }
}
#endif
