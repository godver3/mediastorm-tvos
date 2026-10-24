import SwiftUI

/// The top of a game's page (Expo `SportsEditorialScoreboard` on TV): the competition and
/// state, both sides with logos, rankings, names, records and scores around the game's
/// status (with football's and baseball's live situation, `SportsHeaderSituation`, tennis's set
/// scores, rugby's halves; fights have their own, `SportsCombatHeader`), then the
/// result, delayed-data and starting-soon notes, and when and where it is played. With scores
/// hidden it keeps the names, logos, time and state only.
struct SportsGameHeader: View {
    let page: SportsGamePage
    let spoilers: Bool

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 16) {
                Text(page.leagueName.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                SportsStatusPill(lifecycle: page.lifecycle)
            }
            if page.kind == .mma || page.kind == .boxing {
                SportsCombatHeader(page: page, spoilers: spoilers)
            } else if page.game.isMatchup {
                if page.kind.isRugby {
                    Text(SportsRugby.code(page.kind)).font(.caption).foregroundStyle(.secondary)
                }
                scoreline
            } else {
                VStack(spacing: 10) {
                    Text(page.game.displayTitle).font(.system(size: 52, weight: .semibold)).multilineTextAlignment(.center)
                    if let division = page.game.combat?.division, !division.isEmpty {
                        Text(division).foregroundStyle(.secondary)
                    }
                    Text(spoilers ? SportsFormat.statusLine(page.game, spoilers: true) : SportsFormat.detailStatus(page))
                        .font(.headline)
                }
            }
            notes
            // With scores hidden the page's first panel says when and where.
            if !spoilers, !meta.isEmpty { Text(meta).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
    }

    private var scoreline: some View {
        let teams = page.teams
        let scores = !spoilers && page.game.showsScore
        let situation = SportsHeaderSituation(page: page, spoilers: spoilers)
        return HStack(spacing: 32) {
            side(teams[0], trailing: false, ball: situation.hasBall(teams[0]))
            if scores { score(teams[0], situation: situation) }
            VStack(spacing: 10) {
                Text(center).font(.headline)
                SportsHeaderSituationLines(situation: situation)
                if SportsTennisHeaderSets.shows(page, spoilers: spoilers) { SportsTennisHeaderSets(page: page) }
            }
            .multilineTextAlignment(.center)
            .frame(width: 260)
            if scores { score(teams[1], situation: situation) }
            side(teams[1], trailing: true, ball: situation.hasBall(teams[1]))
        }
    }

    /// The state between the sides; delayed data has its own note under the scores.
    private var center: String {
        if spoilers && page.lifecycle != .scheduled { return SportsFormat.statusLine(page.game, spoilers: true) }
        return page.kind.isRugby ? SportsRugby.status(page) : SportsFormat.detailStatus(page)
    }

    private func score(_ team: SportsTeam, situation: SportsHeaderSituation) -> some View {
        let winner = page.lifecycle == .final && team.winner == true
        // Cricket's score has its overs and target after the runs ("161/5 (18/20 ov, target 156)"): smaller, under them.
        let cricket = page.kind == .cricket
        let full = team.score ?? "–"
        let split = cricket ? full.range(of: " (") : nil
        return VStack(spacing: 6) {
            Text(split.map { String(full[..<$0.lowerBound]) } ?? full)
                .font(.system(size: cricket ? 64 : 88, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(page.lifecycle == .final && !winner ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let split {
                Text(full[split.upperBound...].dropLast(full.hasSuffix(")") ? 1 : 0))
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let football = situation.football {
                SportsTimeouts(count: football.timeouts(for: team, in: page.game), team: team)
            }
        }
        .frame(width: cricket ? 220 : 170)
    }

    /// A side: the logo outside, the name (with a football while it has the ball) and record
    /// towards the centre.
    private func side(_ team: SportsTeam, trailing: Bool, ball: Bool = false) -> some View {
        let name = [spoilers ? nil : team.displayRank.map { "#\($0)" }, team.name,
                    !spoilers && page.kind == .tennis ? team.displaySeed.map { "[\($0)]" } : nil]
            .compactMap { $0 }.joined(separator: " ")
        let record = spoilers ? [] : [team.record, page.isFootballLeague ? team.standingSummary.map { String(localized: "Current: \($0)") } : nil]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        let text = VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
            (ball ? Text("\(name) \(Text(Image(systemName: "football.fill")).foregroundStyle(Color.accentColor))") : Text(name))
                .font(.title3.weight(.semibold)).lineLimit(page.kind == .tennis ? 3 : 2).minimumScaleFactor(0.8)
                .multilineTextAlignment(trailing ? .trailing : .leading)
                .accessibilityLabel(ball ? String(localized: "\(name), has possession") : name)
            if !record.isEmpty { Text(record.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary) }
        }
        return HStack(spacing: 24) {
            if trailing { text }
            SportsTeamLogo(team: team, size: 110)
            if !trailing { text }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    @ViewBuilder private var notes: some View {
        // A fight's header line already names the winner.
        if !spoilers, page.kind != .mma, page.kind != .boxing, let result = SportsFormat.result(page) {
            Text(result).font(.callout.weight(.semibold))
        }
        if !spoilers, page.isStale() {
            Text("Updates delayed · Showing the last available data").font(.caption).foregroundStyle(SportsStatusPill.amber)
        }
        if page.lifecycle == .scheduled, page.game.start.timeIntervalSinceNow < 16 * 60 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let countdown = SportsFormat.pregameCountdown(page.game, now: context.date) {
                    Text("\(countdown) · \(String(localized: "Broadcast availability unconfirmed"))").font(.callout)
                }
            }
        }
    }

    /// When (the status says it before the start), where and on which channels.
    private var meta: String {
        let game = page.game
        return [page.lifecycle == .scheduled ? nil : SportsFormat.startTime(game), game.venue, game.broadcasts?.joined(separator: ", ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}
