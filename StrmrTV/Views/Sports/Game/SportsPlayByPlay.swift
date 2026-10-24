import SwiftUI

/// The Play-by-Play / Commentary tab (Expo `PlaysPanel`): filters (all or scoring plays, and
/// soccer's cards and substitutions or hockey's penalties and shots), the periods, then the
/// plays newest first, 16 to a page. Newer / Older page from the top; Older Plays under the
/// last row turns the page and puts focus on its first play. NFL and college football list their
/// plays on a timeline with each side's logo (Expo `FootballPlays`).
struct SportsPlayByPlay: View {
    let page: SportsGamePage

    @State private var filter: SportsPlayFeed.Filter = .all
    @State private var period: String?
    @State private var pageIndex = 0
    @FocusState private var focus: PlayFocus?

    private enum PlayFocus: Hashable {
        case filter(SportsPlayFeed.Filter), period(String?), newer, older, play(String), more
    }

    var body: some View {
        let feed = SportsPlayFeed(plays: page.detail.plays, kind: page.kind, filter: filter, period: period, page: pageIndex)
        VStack(alignment: .leading, spacing: 22) {
            chips(feed.filters, selected: filter, focus: { .filter($0) }, label: feed.label) { choose(filter: $0) }
            if feed.periods.count > 1 {
                chips([nil] + feed.periods, selected: feed.activePeriod, focus: { .period($0) },
                      label: { $0 ?? String(localized: "All Periods") }) { choose(period: $0) }
            }
            HStack(spacing: 18) {
                if feed.pageCount > 1 {
                    Button("Newer Plays") { turn(to: feed.currentPage - 1, feed: feed, focusFirst: false) }
                        .disabled(feed.currentPage == 0)
                        .opacity(feed.currentPage == 0 ? 0.4 : 1)
                        .focused($focus, equals: .newer)
                    Button("Older Plays") { turn(to: feed.currentPage + 1, feed: feed, focusFirst: false) }
                        .disabled(feed.currentPage == feed.pageCount - 1)
                        .opacity(feed.currentPage == feed.pageCount - 1 ? 0.4 : 1)
                        .focused($focus, equals: .older)
                }
                Text(feed.summary).font(.caption).foregroundStyle(.secondary)
            }
            .buttonStyle(FilterChipStyle(selected: false))
            .font(.callout)
            .sportsChipRow()
            VStack(alignment: .leading, spacing: 10) {
                if feed.visible.isEmpty {
                    Text(feed.emptyText).foregroundStyle(.secondary).sportsReadout()
                }
                ForEach(feed.pagePlays) { play in
                    Group {
                        if page.isFootballLeague {
                            SportsFootballPlayRow(page: page, play: play)
                        } else {
                            SportsPlayRow(page: page, play: play)
                        }
                    }
                    .focused($focus, equals: .play(play.id))
                }
            }
            .font(.callout)
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
            .focusSection()
            if feed.currentPage < feed.pageCount - 1 {
                Button("Older Plays") { turn(to: feed.currentPage + 1, feed: feed, focusFirst: true) }
                    .buttonStyle(FilterChipStyle(selected: false))
                    .font(.callout)
                    .focused($focus, equals: .more)
                    .accessibilityIdentifier("sports-plays-older")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chips<Value: Hashable>(_ values: [Value], selected: Value, focus target: @escaping (Value) -> PlayFocus,
                                        label: @escaping (Value) -> String, choose: @escaping (Value) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 18) {
                ForEach(values, id: \.self) { value in
                    Button(label(value)) { choose(value) }
                        .buttonStyle(FilterChipStyle(selected: value == selected))
                        .focused($focus, equals: target(value))
                }
            }
            .padding(.vertical, 12)
        }
        .scrollClipDisabled()
        .font(.callout)
        .focusSection()
        .defaultFocus($focus, target(selected), priority: .userInitiated)
    }

    private func choose(filter: SportsPlayFeed.Filter) {
        self.filter = filter
        pageIndex = 0
    }

    private func choose(period: String?) {
        self.period = period
        pageIndex = 0
    }

    /// Turns the page; from under the list, focus moves to the new page's first play.
    private func turn(to index: Int, feed: SportsPlayFeed, focusFirst: Bool) {
        var next = feed
        next.page = index
        pageIndex = next.currentPage
        guard focusFirst, let first = next.pagePlays.first else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            focus = .play(first.id)
        }
    }
}
