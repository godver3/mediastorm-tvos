import SwiftUI

/// A game on the Sports hub: league and status across the top, then the two sides with their
/// logos and scores (home first for team sports, Expo `sportsOrderedTeams`; or a non-matchup
/// event's title), a live game's context line (`SportsCardFooter`), and when it starts or how it
/// stands, with "Updates delayed" when its league's scoreboard is serving older data. A score that
/// changes between refreshes lights the card for two seconds (Expo `SportsCardFrame`). With scores
/// hidden it keeps names, times and the LIVE / FINAL state only.
struct SportsGameCard: View {
    static let width: CGFloat = 460
    /// Room for two score lines, a context line and the status line; every card is this tall.
    static let height: CGFloat = 300

    let game: SportsGame
    let leagueName: String
    let kind: SportsKind
    let spoilers: Bool
    var stale = false

    @FocusState private var isFocused: Bool
    @State private var flashes = 0
    @State private var flashing = false

    var body: some View {
        NavigationLink(value: SportsGameRef(id: game.id, title: game.displayTitle)) {
            VStack(alignment: .leading, spacing: 0) {
                switch SportsCardVariant(game: game, kind: kind) {
                case .tennis: SportsTennisCard(game: game, leagueName: leagueName, spoilers: spoilers, stale: stale)
                case .combat: SportsCombatCard(game: game, leagueName: leagueName, spoilers: spoilers, stale: stale)
                case .field: SportsFieldCard(game: game, leagueName: leagueName, kind: kind, spoilers: spoilers, stale: stale)
                case .matchup: matchup
                }
            }
            .padding(22)
            .frame(width: Self.width, height: Self.height, alignment: .topLeading)
            .background(Color.white.opacity(isFocused ? 0.16 : 0.08))
            .overlay { flash }
        }
        .buttonStyle(PosterFocusStyle(isFocused: isFocused))
        .focused($isFocused)
        .accessibilityIdentifier("sports-card-\(game.id)")
        .onChange(of: SportsScoreChange.key(game, spoilers: spoilers)) { old, new in
            if SportsScoreChange.changed(from: old, to: new) { flashes += 1 }
        }
        .task(id: flashes) {
            guard flashes > 0 else { return }
            flashing = true
            try? await Task.sleep(for: SportsScoreChange.duration)
            guard !Task.isCancelled else { return }
            flashing = false
        }
    }

    /// A team game's card: the sides with logos and scores, the context line and the status.
    private var matchup: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SportsCardHeading(leagueName: leagueName, lifecycle: game.lifecycle)
                if game.isMatchup {
                    ForEach(sides, id: \.id) { team in
                        SportsTeamLine(team: team, score: kind == .cricket ? nil : score(team), leads: leads(team),
                                       detail: kind == .cricket ? score(team) : nil, record: record(team))
                    }
                } else {
                    Text(game.displayTitle).font(.headline).lineLimit(2)
                    if let division = game.combat?.division, !division.isEmpty {
                        Text(division).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 6) {
                // Cricket's reported state ("RCB need 36 runs in 30 balls") is already the status line.
                if let footer = SportsCardFooter.make(game, kind: kind, spoilers: spoilers), footer.text != game.statusDetail {
                    SportsCardFooterLine(footer: footer)
                }
                status
            }
        }
    }

    /// Display order: home first, away first for tennis, combat and golf.
    private var sides: [SportsTeam] { kind.awayFirst ? [game.awayTeam, game.homeTeam] : [game.homeTeam, game.awayTeam] }

    /// The state line; a scheduled game's countdown refreshes every 30 s.
    @ViewBuilder private var status: some View {
        if game.lifecycle == .scheduled {
            TimelineView(.periodic(from: .now, by: 30)) { context in statusText(now: context.date) }
        } else {
            statusText(now: Date())
        }
    }

    private func statusText(now: Date) -> some View {
        let line = Text(SportsFormat.statusLine(game, spoilers: spoilers, now: now)).foregroundStyle(.secondary)
        return (stale ? line + Text(" · ").foregroundStyle(.secondary)
                + Text("Updates delayed").foregroundStyle(SportsStatusPill.amber) : line)
            .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
    }

    /// The score-change cue: an accent outline and bar, fading out (focus never moves).
    private var flash: some View {
        RoundedRectangle(cornerRadius: PosterFocusStyle.cornerRadius, style: .continuous)
            .strokeBorder(SportsStatusPill.accent, lineWidth: 3)
            .overlay(alignment: .bottom) {
                Capsule().fill(SportsStatusPill.accent).frame(height: 4).padding(.horizontal, 18).padding(.bottom, 8)
            }
            .opacity(flashing ? 1 : 0)
            .animation(.easeOut(duration: 0.3), value: flashing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func score(_ team: SportsTeam) -> String? {
        spoilers || !game.showsScore ? nil : team.score
    }

    /// A record (from the scoreboard or the league's table) while there is no score to show.
    private func record(_ team: SportsTeam) -> String? {
        spoilers || score(team) != nil ? nil : team.record
    }

    private func leads(_ team: SportsTeam) -> Bool {
        !spoilers && game.lifecycle == .final && team.winner == true
    }
}

/// A live card's context: MLB's bases glyph or the sport's symbol, then the situation.
struct SportsCardFooterLine: View {
    let footer: SportsCardFooter

    var body: some View {
        HStack(spacing: 10) {
            if let bases = footer.bases {
                SportsBasesGlyph(bases: bases, size: 15)
            } else if let symbol = footer.symbol {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            if !footer.text.isEmpty { Text(footer.text).lineLimit(1) }
        }
        .font(.caption.weight(.medium))
        .accessibilityElement(children: .combine)
    }
}

/// One side of a matchup: logo, name and score (or the side's record, muted).
struct SportsTeamLine: View {
    let team: SportsTeam
    let score: String?
    let leads: Bool
    var logoSize: CGFloat = 44
    /// A line under the name (cricket's "161/5 (18/20 ov, target 156)").
    var detail: String?
    /// Shown muted where the score goes while there is none.
    var record: String?

    var body: some View {
        HStack(spacing: 14) {
            SportsTeamLogo(team: team, size: logoSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name).font(.callout.weight(leads ? .bold : .medium)).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(leads ? .primary : .secondary).monospacedDigit().lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let score {
                Text(score).font(.title3.weight(leads ? .bold : .semibold)).monospacedDigit()
                    .foregroundStyle(leads || score.isEmpty ? .primary : .secondary)
            } else if let record, !record.isEmpty {
                Text(record).font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct SportsTeamLogo: View {
    let team: SportsTeam
    let size: CGFloat

    var body: some View {
        RemoteImage(url: team.logo, size: CGSize(width: size, height: size), contentMode: .fit) { _ in
            Circle().fill(team.color.flatMap(Color.init(hex:)) ?? Color.white.opacity(0.15))
                .overlay(Text(team.monogram).font(.system(size: size * 0.3, weight: .bold)))
        }
        .frame(width: size, height: size)
    }
}

struct SportsStatusPill: View {
    let lifecycle: SportsLifecycle

    var body: some View {
        HStack(spacing: 6) {
            if lifecycle == .live { Circle().fill(Self.live).frame(width: 10, height: 10) }
            Text(lifecycle.pill).font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Capsule().fill(background))
        .foregroundStyle(lifecycle.isScheduleChange ? Self.amber : .primary)
    }

    private var background: Color {
        lifecycle == .live ? Self.live.opacity(0.22) : Color.white.opacity(0.12)
    }

    static let live = Color(red: 1, green: 0.2, blue: 0.3)
    static let amber = Color(red: 0.9, green: 0.72, blue: 0.35)
    /// Expo's sports accent (#00c8f0): a card's score-change cue.
    static let accent = Color(red: 0, green: 0.784, blue: 0.941)
}

/// Value pushed to open a game's page.
struct SportsGameRef: Hashable {
    let id: String
    let title: String
}

enum SportsFormat {
    /// "7:05 PM · Starts in 2h 5m", the live clock, or the final line.
    static func statusLine(_ game: SportsGame, spoilers: Bool, now: Date = Date()) -> String {
        switch game.lifecycle {
        case .scheduled:
            // The time, then Expo's countdown ("Starts in 2h 5m", "Awaiting start").
            let countdown = countdown(to: game.start, now: now)
            guard game.start != .distantPast else { return countdown }
            return "\(game.start.formatted(date: .omitted, time: .shortened)) · \(countdown)"
        case .live:
            if spoilers { return String(localized: "In progress · scores hidden") }
            return game.statusDetail ?? [game.period, game.clock].compactMap { $0 }.joined(separator: " · ")
        case .final:
            return spoilers ? String(localized: "Result hidden") : (game.statusDetail ?? String(localized: "Final"))
        case .delayed, .postponed, .canceled:
            return game.statusDetail ?? startTime(game)
        }
    }

    static func startTime(_ game: SportsGame) -> String {
        let calendar = Calendar.current
        let time = game.start.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(game.start) { return time }
        return "\(game.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(time)"
    }
}
