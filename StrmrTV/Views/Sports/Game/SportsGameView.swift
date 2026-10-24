import SwiftUI

/// A game's page (Expo `app/sports/[eventId].tsx` with `SportsGameDetailTV`): the scoreboard,
/// Watch Live / Find Streams and Hide Scores, then the tabs the feed can fill (Overview, the
/// sport's own, Box Score, Play-by-Play, Standings) and the shown tab's panels. The tab picked
/// is kept while the page is open. With scores hidden there are no tabs: only what was known
/// before the start shows. Refreshed every 30 s while live, 60 s otherwise.
struct SportsGameView: View {
    let ref: SportsGameRef
    let leagues: [String: SportsLeague]

    @ObservedObject private var spoilers = SportsSpoilers.shared
    @State private var game: SportsGame?
    @State private var error: String?
    @State private var picking = false
    /// The stream picked, tuned once the picker has gone (the player can't present over it).
    @State private var chosen: SportsStreamMatch?
    @State private var selectedTab: SportsGameTab = .overview
    /// The player line the Box Score opens on (picked on MLB's Overview); dropped on leaving it.
    @State private var playerTarget: SportsPlayerTarget?
    @FocusState private var focus: SportsGameFocus?

    private static let top = "sports-game-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 40) {
                    if let game {
                        content(SportsGamePage(game: game, league: leagues[game.league]))
                    } else if let error {
                        // Focusable, so the page has a focused element and Menu goes back to the hub
                        // instead of leaving the app (a fight card's bout the server doesn't list answers 404).
                        Text(error).foregroundStyle(.secondary).sportsReadout(fill: false).padding(.top, 200)
                    } else {
                        ProgressView().padding(.top, 260)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, CardGridLayout.inset)
                // Clear of the menu's tab pill.
                .padding(.top, 90)
                .padding(.bottom, 80)
            }
            // Back up in the controls, the scoreboard shows again.
            .onChange(of: focus) { _, new in
                guard new != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(Self.top, anchor: .top) }
            }
            .environment(\.sportsPageScroll, SportsPageAction { target in
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target.id, anchor: target.anchor) }
            })
        }
        .defaultFocus($focus, initialFocus)
        // A player picked on the Overview is opened once: leaving the Box Score or hiding the
        // scores (which takes the tabs away) drops it.
        .onChange(of: selectedTab) { _, tab in
            if tab != .stats { playerTarget = nil }
        }
        .onChange(of: spoilers.hidden) { playerTarget = nil }
        .task(id: ref.id) { await refreshLoop() }
        .fullScreenCover(isPresented: $picking, onDismiss: tuneChosen) {
            if let game {
                SportsStreamPicker(game: game) { match in
                    chosen = match
                    picking = false
                }
            }
        }
    }

    @ViewBuilder private func content(_ page: SportsGamePage) -> some View {
        let tabs = SportsGameTab.available(for: page, spoilers: spoilers.hidden)
        let shown = SportsGameTab.shown(selectedTab, in: tabs)
        SportsGameHeader(page: page, spoilers: spoilers.hidden).id(Self.top)
        VStack(spacing: 28) {
            actions(page.game)
            if !tabs.isEmpty {
                SportsGameTabRow(tabs: tabs, kind: page.kind, shown: shown, focus: $focus) { selectedTab = $0 }
            }
        }
        Group {
            if spoilers.hidden {
                SportsSpoilerOverview(page: page)
            } else {
                SportsGameContent(page: page, tab: shown, playerTarget: playerTarget)
                    .environment(\.sportsShowPlayer, SportsPageAction { target in
                        playerTarget = target
                        selectedTab = .stats
                    })
                Text(SportsFormat.freshness(page, stale: page.isStale()))
                    .font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Watch when there is something to watch, else the Overview tab (Expo's default focus).
    private var initialFocus: SportsGameFocus {
        guard let game else { return .spoilers }
        if canWatch(game) { return .watch }
        return spoilers.hidden ? .spoilers : .tab(.overview)
    }

    private func canWatch(_ game: SportsGame) -> Bool {
        [.live, .scheduled, .delayed].contains(game.lifecycle)
    }

    private func actions(_ game: SportsGame) -> some View {
        HStack(spacing: 24) {
            if canWatch(game) {
                Button { picking = true } label: {
                    Label(game.lifecycle == .live ? "Watch Live" : "Find Streams", systemImage: "play.fill")
                }
                .focused($focus, equals: .watch)
                .accessibilityIdentifier("sports-watch")
            }
            Button { spoilers.hidden.toggle() } label: {
                Label(spoilers.hidden ? "Show Scores" : "Hide Scores", systemImage: spoilers.hidden ? "eye" : "eye.slash")
            }
            .focused($focus, equals: .spoilers)
            .accessibilityIdentifier("sports-detail-spoilers")
        }
        .sportsChipRow(alignment: .center)
    }

    private func tuneChosen() {
        guard let match = chosen else { return }
        chosen = nil
        LivePlayback.play(match.channel, program: nil)
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            do {
                game = try await APIClient.shared.sportsGame(ref.id)
                error = nil
            } catch {
                if !(error is CancellationError), game == nil { self.error = error.localizedDescription }
            }
            try? await Task.sleep(for: .seconds(game?.lifecycle == .live ? 30 : 60))
        }
    }
}
