#if os(iOS)
import SwiftUI

/// The top of a game's page on a phone (Expo `SportsEditorialScoreboard`, mobile layout): the
/// competition and state, then both sides with logo, rank, name and record over their scores,
/// the status between them with the live situation (`SportsHeaderSituation`: down and distance,
/// runners and outs, possession), tennis's sets, then the result, delayed-data and starting-soon
/// notes and when and where it is played. A fight shows both fighters' portraits either side of "VS"; an event
/// that is not a matchup shows its title. With scores hidden: names, logos, time and state only.
struct MobileSportsGameHeader: View {
    let page: SportsGamePage
    let spoilers: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Text(page.leagueName.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if page.kind.isRugby {
                    Text(SportsRugby.code(page.kind)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SportsStatusPill(lifecycle: page.lifecycle)
            }
            if page.kind == .mma || page.kind == .boxing {
                combat
            } else if page.game.isMatchup {
                scoreline
            } else {
                VStack(spacing: 6) {
                    Text(page.game.displayTitle).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    if let division = page.game.combat?.division, !division.isEmpty {
                        Text(division).foregroundStyle(.secondary)
                    }
                    Text(spoilers ? SportsFormat.statusLine(page.game, spoilers: true) : SportsFormat.detailStatus(page))
                        .font(.headline)
                }
            }
            notes
            if !spoilers, !meta.isEmpty {
                Text(meta).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var scoreline: some View {
        let teams = page.teams
        let situation = SportsHeaderSituation(page: page, spoilers: spoilers)
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                side(teams[0], ball: situation.hasBall(teams[0]), situation: situation)
                VStack(spacing: 6) {
                    Text(center).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                    SportsHeaderSituationLines(situation: situation).font(.footnote)
                }
                .frame(minWidth: 84, maxWidth: 120)
                .padding(.top, 18)
                side(teams[1], ball: situation.hasBall(teams[1]), situation: situation)
            }
            if SportsTennisHeaderSets.shows(page, spoilers: spoilers) { SportsTennisHeaderSets(page: page) }
        }
    }

    /// A fight (the TV's `SportsCombatHeader`, upright): both fighters, the winner tagged, and the
    /// result or start; a card without named fighters shows its title.
    private var combat: some View {
        let game = page.game
        let named = SportsCombatRules.named(game)
        let line: String = if page.lifecycle == .scheduled {
            [game.combat?.division, SportsFormat.detailStatus(page)].compactMap { $0 }.joined(separator: " · ")
        } else if spoilers || named {
            SportsCombatRules.result(game, hidden: spoilers)
        } else {
            game.statusDetail.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Result not supplied")
        }
        return VStack(spacing: 10) {
            if named {
                HStack(alignment: .top, spacing: 8) {
                    fighter(game.awayTeam)
                    Text("VS").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 34)
                    fighter(game.homeTeam)
                }
            } else {
                Text(game.displayTitle).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            }
            Text(line).font(.headline).multilineTextAlignment(.center)
        }
    }

    private func fighter(_ athlete: SportsTeam) -> some View {
        VStack(spacing: 6) {
            SportsPlayerPortrait(name: athlete.name, headshot: SportsCombatRules.portrait(league: page.game.league, fighter: athlete),
                                 size: 84)
            Text(athlete.name).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
            if !spoilers, page.lifecycle == .final, athlete.winner == true {
                Text("WINNER").font(.caption2.weight(.bold)).foregroundStyle(SportsCombatHeader.winner)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var center: String {
        if spoilers && page.lifecycle != .scheduled { return SportsFormat.statusLine(page.game, spoilers: true) }
        return page.kind.isRugby ? SportsRugby.status(page) : SportsFormat.detailStatus(page)
    }

    /// A side: logo, name (with a football while it has the ball), record, then the score.
    private func side(_ team: SportsTeam, ball: Bool, situation: SportsHeaderSituation) -> some View {
        let name = [spoilers ? nil : team.displayRank.map { "#\($0)" }, team.name,
                    !spoilers && page.kind == .tennis ? team.displaySeed.map { "[\($0)]" } : nil]
            .compactMap { $0 }.joined(separator: " ")
        let record = spoilers ? [] : [team.record, page.isFootballLeague ? team.standingSummary : nil]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        let winner = page.lifecycle == .final && team.winner == true
        return VStack(spacing: 6) {
            SportsTeamLogo(team: team, size: 56)
            (ball ? Text("\(name) \(Text(Image(systemName: "football.fill")).foregroundStyle(Color.accentColor))") : Text(name))
                .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center).lineLimit(3)
                .accessibilityLabel(ball ? String(localized: "\(name), has possession") : name)
            if !record.isEmpty {
                Text(record.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if !spoilers, page.game.showsScore { score(team, winner: winner) }
            if let football = situation.football {
                SportsTimeouts(count: football.timeouts(for: team, in: page.game), team: team)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The score; cricket's overs and target go under the runs, smaller.
    @ViewBuilder private func score(_ team: SportsTeam, winner: Bool) -> some View {
        let full = team.score ?? "–"
        let split = page.kind == .cricket ? full.range(of: " (") : nil
        Text(split.map { String(full[..<$0.lowerBound]) } ?? full)
            .font(.system(.largeTitle, weight: .bold)).monospacedDigit()
            .foregroundStyle(page.lifecycle == .final && !winner ? .secondary : .primary)
            .lineLimit(1).minimumScaleFactor(0.5)
        if let split {
            Text(full[split.upperBound...].dropLast(full.hasSuffix(")") ? 1 : 0))
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var notes: some View {
        if !spoilers, page.kind != .mma, page.kind != .boxing, let result = SportsFormat.result(page) {
            Text(result).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
        }
        if !spoilers, page.isStale() {
            Label("Updates delayed · Showing the last available data", systemImage: "clock.badge.exclamationmark")
                .font(.caption).foregroundStyle(SportsStatusPill.amber)
        }
        if page.lifecycle == .scheduled, page.game.start.timeIntervalSinceNow < 16 * 60 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let countdown = SportsFormat.pregameCountdown(page.game, now: context.date) {
                    Text("\(countdown) · \(String(localized: "Broadcast availability unconfirmed"))").font(.footnote)
                }
            }
        }
    }

    private var meta: String {
        let game = page.game
        return [page.lifecycle == .scheduled ? nil : SportsFormat.startTime(game), game.venue, game.broadcasts?.joined(separator: ", ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}
#endif
