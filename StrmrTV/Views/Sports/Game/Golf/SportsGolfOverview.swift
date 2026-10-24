import SwiftUI

/// The Overview of PGA and LPGA tournaments (Expo `SportsGolfOverview`, its TV layout): the
/// leaderboard in the feed's order, eight golfers a page with each round's strokes and the score
/// to par, beside the chosen golfer's scorecard. Select on a golfer shows their card; the round
/// chips switch rounds. Scores are the provider's; the row order isn't presented as a rank.
struct SportsGolfOverview: View {
    let page: SportsGamePage

    @State private var selected: String?
    @State private var round: Int?
    @State private var pageIndex = 0

    static let pageSize = 8

    private var players: [SportsGolfEntry] { page.lifecycle == .scheduled ? [] : page.detail.leaderboard }
    private var player: SportsGolfEntry? { players.first { $0.id == selected } ?? players.first }

    var body: some View {
        SportsColumns(weights: [1.2, 1]) {
            leaderboard.frame(maxHeight: .infinity, alignment: .top).focusSection()
            SportsGolfScorecard(page: page, player: player, round: $round)
                .frame(maxHeight: .infinity, alignment: .top).focusSection()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: page.game.id) {
            selected = nil
            round = nil
            pageIndex = 0
        }
    }

    private var leaderboard: some View {
        let pages = max(1, Int((Double(players.count) / Double(Self.pageSize)).rounded(.up)))
        let current = min(pageIndex, pages - 1)
        let visible = Array(players.dropFirst(current * Self.pageSize).prefix(Self.pageSize))
        return SportsPanel(String(localized: "Leaderboard"),
                           note: players.isEmpty ? nil : String(localized: "\(players.count) golfers · Provider order")) {
            if pages > 1 {
                HStack(spacing: 18) {
                    // Dimmed, not disabled, at either end: a disabled chip would drop the remote's focus.
                    Button("Previous Golfers") { pageIndex = max(0, current - 1) }
                        .buttonStyle(FilterChipStyle(selected: false)).opacity(current == 0 ? 0.45 : 1)
                    Button("Next Golfers") { pageIndex = min(pages - 1, current + 1) }
                        .buttonStyle(FilterChipStyle(selected: false)).opacity(current == pages - 1 ? 0.45 : 1)
                    Text("\(current + 1) / \(pages)").font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
                .focusSection()
            }
            HStack(spacing: 8) {
                Text("Player").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(1...4, id: \.self) { Text("R\($0)").frame(width: 64) }
                Text("To par").frame(width: 100)
            }
            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            if visible.isEmpty {
                Text(page.lifecycle == .scheduled ? "Scores will appear when play begins." : "Leaderboard not available yet.")
                    .foregroundStyle(.secondary).sportsReadout()
            }
            ForEach(visible) { golfer in
                Button {
                    selected = golfer.id
                    round = nil
                } label: {
                    HStack(spacing: 8) {
                        Text(golfer.name).fontWeight(.semibold).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(1...4, id: \.self) { number in
                            Text(golfer.rounds.first { $0.round == number }?.strokes ?? "–").foregroundStyle(.secondary).frame(width: 64)
                        }
                        Text(golfer.score ?? "–").fontWeight(.bold).frame(width: 100)
                    }
                    .monospacedDigit()
                }
                .buttonStyle(SportsReadoutButtonStyle(chosen: golfer.id == player?.id))
                .accessibilityLabel(String(localized: "\(golfer.name), \(golfer.score ?? String(localized: "score unavailable")), view scorecard"))
            }
        }
    }
}

/// A golfer's scorecard (Expo `SportsGolfOverview`'s scorecard panel): the tournament score to
/// par, a chip per round ("R2 · 68"), then the round's front and back nine hole by hole, teal
/// below par and warm above; the venue and channels under it. One stop per nine.
struct SportsGolfScorecard: View {
    let page: SportsGamePage
    let player: SportsGolfEntry?
    @Binding var round: Int?

    private static let under = Color(red: 0.086, green: 0.24, blue: 0.255)
    private static let over = Color(red: 0.28, green: 0.2, blue: 0.19)
    private static let even = Color(red: 0.13, green: 0.19, blue: 0.27)

    var body: some View {
        let rounds = player?.rounds ?? []
        let shown = rounds.first { $0.round == round } ?? rounds.last
        SportsPanel(player.map { String(localized: "\($0.name) · Round Scores") } ?? String(localized: "Scorecard")) {
            if let player {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tournament · To par").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(player.score ?? "–").font(.system(size: 44, weight: .bold)).monospacedDigit()
                }
                .sportsReadout()
                if !rounds.isEmpty {
                    HStack(spacing: 14) {
                        ForEach(rounds, id: \.round) { item in
                            Button("R\(item.round) · \(item.strokes ?? "–")") { round = item.round }
                                .buttonStyle(FilterChipStyle(selected: item.round == shown?.round))
                        }
                    }
                    .font(.callout)
                    .focusSection()
                }
                if let shown {
                    Text([String(localized: "Round \(shown.round)"), String(localized: "\(shown.strokes ?? "–") strokes"),
                          shown.toPar.map { String(localized: "\($0) to par") }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    nine(shown, from: 1, title: String(localized: "Front Nine"))
                    nine(shown, from: 10, title: String(localized: "Back Nine"))
                    Text("Hole scores · Teal below par · Warm above par").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Round and hole scores have not been supplied.").foregroundStyle(.secondary)
                }
            } else {
                Text("Select a golfer when the leaderboard is available.").foregroundStyle(.secondary).sportsReadout()
            }
            let place = [page.game.venue, page.game.broadcasts?.joined(separator: " · ")].compactMap { $0?.isEmpty == false ? $0 : nil }
            if !place.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(place, id: \.self) { Text($0) }
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }

    private func nine(_ round: SportsGolfRound, from start: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(start..<(start + 9), id: \.self) { number in
                    let hole = round.holes.first { $0.hole == number }
                    let par = hole?.toPar ?? ""
                    VStack(spacing: 6) {
                        Text("\(number)").font(.caption2).foregroundStyle(.secondary)
                        Text(hole?.strokes.isEmpty == false ? hole!.strokes : "–").fontWeight(.semibold)
                    }
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(par.hasPrefix("-") ? Self.under : par.hasPrefix("+") ? Self.over : Self.even))
                }
            }
        }
        .sportsReadout()
        .accessibilityLabel(String(localized: "Round \(round.round), holes \(start) to \(start + 8)"))
    }
}
