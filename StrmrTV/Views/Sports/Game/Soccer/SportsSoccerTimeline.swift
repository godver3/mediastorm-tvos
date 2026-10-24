import SwiftUI

/// The soccer Overview's events (Expo `SportsMatchTimeline`, compact): the match's goals in order
/// (scorer, minute, side; own goals marked), then the newest event ("Latest Event", "Last Reported
/// Event" once final, "Last Available Event" when the data is old) with its symbol in the side's
/// colour, the minute, title and narrative. Full history in Commentary. One stop per goal and event.
struct SportsSoccerTimeline: View {
    let page: SportsGamePage

    /// The newest play with text (Expo `sportsTimelineEvents`, first one).
    nonisolated static func latest(_ page: SportsGamePage) -> SportsPlay? {
        guard page.lifecycle != .scheduled else { return nil }
        return page.detail.plays.first { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
            || !($0.description ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Up to eight goals other than the latest event, oldest first.
    nonisolated static func goals(_ page: SportsGamePage) -> [SportsPlay] {
        let latest = latest(page)?.id
        var seen = Set<String>()
        let goals = page.detail.plays.filter { play in
            seen.insert(play.id).inserted && !play.shootout && SportsEventKind(title: play.title) == .goal && play.id != latest
        }
        return goals.prefix(8).reversed()
    }

    var body: some View {
        let goals = Self.goals(page)
        SportsPanel(title, note: String(localized: "Latest update · Full history in Commentary")) {
            if !goals.isEmpty {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(goals) { goal($0) }
                    }
                    .padding(.horizontal, 14)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -14)
            }
            if let play = Self.latest(page) { event(play) }
        }
    }

    private var title: String {
        if page.lifecycle == .final { return String(localized: "Last Reported Event") }
        return page.isStale() ? String(localized: "Last Available Event") : String(localized: "Latest Event")
    }

    private func color(_ play: SportsPlay) -> Color {
        page.team(id: play.teamId).map { SportsTeamColors.color($0, in: page.game) } ?? .secondary
    }

    private func goal(_ play: SportsPlay) -> some View {
        let team = page.team(id: play.teamId)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SportsSoccerEventIcon(play: play, color: color(play), size: 36)
                Text(play.clock ?? play.periodLabel).font(.caption).foregroundStyle(SportsStatusPill.accent).monospacedDigit()
                if let team { Text(team.shortName).font(.caption).foregroundStyle(.secondary) }
            }
            Text(play.participants.first?.name ?? play.title).font(.callout.weight(.semibold)).lineLimit(1)
            if SportsFormat.matches("own", play.title) {
                Text("Own goal").font(.caption2).foregroundStyle(SportsStatusPill.accent)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
        .sportsReadout(fill: false)
        .accessibilityLabel([play.clock, team?.name, play.participants.first?.name, play.description ?? play.title]
            .compactMap { $0 }.joined(separator: " · "))
    }

    private func event(_ play: SportsPlay) -> some View {
        let team = page.team(id: play.teamId)
        let time = [play.clock, play.periodLabel].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 18) {
            SportsSoccerEventIcon(play: play, color: color(play), size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text([time.isEmpty ? String(localized: "Time not supplied") : time, team?.shortName,
                      play.shootout ? String(localized: "Shootout") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(SportsStatusPill.accent).monospacedDigit()
                Text(play.title.isEmpty ? String(localized: "Reported event") : play.title).fontWeight(.semibold)
                if let description = play.description {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } else if !play.participants.isEmpty {
                    Text(play.participants.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .sportsReadout()
    }
}

/// A soccer event's symbol from its title (Expo `EventIcon` over `sportsTimelineKind`): a ball for
/// goals, the card itself (both for a second yellow), a swap for substitutions, a warning for
/// penalties, a flag for corners and offsides, a pause for the whistle; a dot otherwise.
struct SportsSoccerEventIcon: View {
    let play: SportsPlay
    let color: Color
    var size: CGFloat = 40

    private static let yellow = Color(red: 0.98, green: 0.75, blue: 0.14)
    private static let red = Color(red: 0.94, green: 0.27, blue: 0.27)

    var body: some View {
        Group {
            switch SportsEventKind(title: play.title) {
            case .yellowCard: card(Self.yellow)
            case .redCard:
                if SportsFormat.matches(#"^(second yellow( card)?|yellow red card)$"#, play.title.trimmingCharacters(in: .whitespaces)) {
                    ZStack { card(Self.yellow).offset(x: -size * 0.1, y: -size * 0.06); card(Self.red).offset(x: size * 0.1, y: size * 0.06) }
                } else {
                    card(Self.red)
                }
            case .goal: symbol("soccerball")
            case .substitution: symbol("arrow.left.arrow.right")
            case .penalty: symbol("exclamationmark.circle", tint: Self.yellow)
            case .other: symbol(otherSymbol)
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(Color.white.opacity(0.08)))
        .accessibilityHidden(true)
    }

    private var otherSymbol: String {
        let title = play.title.lowercased()
        if SportsFormat.matches("^(corner|corner kick|offside|offsides)$", title) { return "flag.fill" }
        if SportsFormat.matches("^(foul|foul committed|foul conceded)$", title) { return "exclamationmark.triangle" }
        if SportsFormat.matches("^(kick ?off|half ?time|full time|end of match)$", title) { return "pause.circle" }
        return "circle.fill"
    }

    private func symbol(_ name: String, tint: Color? = nil) -> some View {
        Image(systemName: name).font(.system(size: size * (name == "circle.fill" ? 0.25 : 0.52), weight: .semibold))
            .foregroundStyle(tint ?? color)
    }

    private func card(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.06).fill(fill).frame(width: size * 0.38, height: size * 0.56)
    }
}
