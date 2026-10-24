import SwiftUI

/// The Overview of cricket matches (Expo `SportsSportOverview`'s cricket branch): the innings
/// scorecard beside the reported highlights, the player scorecards and the match information.
struct SportsCricketOverview: View {
    let page: SportsGamePage

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            SportsColumns(weights: [1.2, 1]) {
                SportsCricketInningsPanel(page: page)
                    .frame(maxHeight: .infinity, alignment: .top).focusSection()
                VStack(alignment: .leading, spacing: 24) {
                    SportsCricketScorecards(page: page)
                    if !SportsMatchInfo.items(page).isEmpty || SportsMatchInfo.hasNotes(page) { SportsMatchInfo(page: page) }
                }
                .frame(maxHeight: .infinity, alignment: .top).focusSection()
            }
            if page.lifecycle == .scheduled {
                SportsPregamePreview(page: page, pregame: page.detail.pregame)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every innings (Expo `SportsCricketOverview`, "Innings scorecard"): the reported state or result,
/// then per innings the side, its label ("1st innings", "Batting · 2nd innings"), the score and
/// overs, and for the side chasing the target, runs needed and a progress bar. One stop each.
struct SportsCricketInningsPanel: View {
    let page: SportsGamePage

    var body: some View {
        let lines = SportsCricket.lines(page)
        let final = page.lifecycle == .final
        SportsPanel(String(localized: "Innings Scorecard")) {
            Text(SportsFormat.detailStatus(page))
                .font(final ? .title3.weight(.bold) : .callout)
                .foregroundStyle(final ? .primary : .secondary)
            if lines.isEmpty {
                Text(page.lifecycle == .scheduled ? "Innings will appear when play begins." : "Innings details have not been supplied.")
                    .foregroundStyle(.secondary).sportsReadout()
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in row(line) }
        }
    }

    private func row(_ line: SportsCricket.Line) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 16) {
                if let team = line.team { SportsTeamLogo(team: team, size: 40) }
                Text(line.team?.name ?? String(localized: "Team not supplied")).font(.headline)
                Spacer(minLength: 12)
                Text(line.current ? "\(line.state) · \(line.label)" : line.state).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(line.score).font(.system(size: line.current ? 48 : 38, weight: line.current ? .bold : .semibold)).monospacedDigit()
                if let overs = line.innings.overs { Text("\(overs) overs").foregroundStyle(.secondary) }
            }
            if let progress = line.progress {
                GeometryReader { proxy in
                    Capsule().fill(Color.white.opacity(0.14))
                        .overlay(alignment: .leading) { Capsule().fill(Color.white).frame(width: proxy.size.width * progress) }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            if !line.chase.isEmpty { Text(line.chase).fontWeight(.semibold) }
            if let description = line.innings.description { Text(description).font(.caption).foregroundStyle(.secondary) }
        }
        .sportsReadout()
        .accessibilityLabel([line.team?.name ?? String(localized: "Team not supplied"), line.state, line.label, line.score,
                             line.innings.overs.map { String(localized: "\($0) overs") }, line.chase, line.innings.description]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ". "))
    }
}

/// The player scorecards (Expo `SportsCricketScorecards`): a final's top batters and bowlers of the
/// last innings ("Reported Innings 2 Highlights"), then each batting and bowling card with every
/// player's figures and dismissal and the extras. One stop per player.
struct SportsCricketScorecards: View {
    let page: SportsGamePage

    var body: some View {
        let cards = page.lifecycle == .scheduled ? [] : page.detail.cricketScorecards
        let highlights = SportsCricket.highlights(page)
        VStack(alignment: .leading, spacing: 24) {
            if !highlights.players.isEmpty {
                SportsPanel(String(localized: "Reported Innings \(highlights.innings) Highlights")) {
                    ForEach(Array(highlights.players.enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 16) {
                            SportsPlayerPortrait(name: entry.player.name, headshot: entry.player.headshotUrl, size: 48)
                            Text(entry.player.name).fontWeight(.semibold)
                            Spacer()
                            Text("\(entry.value) \(entry.metric)").fontWeight(.bold)
                        }
                        .sportsReadout()
                    }
                }
            }
            if !cards.isEmpty {
                Text("Reported player scorecards · Available innings only").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                SportsPanel("\(card.teamName) · \(card.kind == .batting ? String(localized: "Batting") : String(localized: "Bowling"))",
                            note: [String(localized: "Match innings \(card.innings)"), page.isStale() ? String(localized: "Last reported") : nil]
                                .compactMap { $0 }.joined(separator: " · ")) {
                    ForEach(card.players) { player($0) }
                    if let extras = card.extras { Text("Extras \(extras)").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func player(_ player: SportsCricketPlayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                SportsPlayerPortrait(name: player.name, headshot: player.headshotUrl, size: 40)
                Text(player.name).fontWeight(.semibold)
            }
            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(player.stats.enumerated()), id: \.offset) { _, stat in
                    SportsFigure(label: stat.label, value: stat.value)
                }
            }
            if let dismissal = player.dismissal { Text(dismissal).font(.caption).foregroundStyle(.secondary) }
        }
        .sportsReadout()
    }
}
