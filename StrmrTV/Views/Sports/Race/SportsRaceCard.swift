import SwiftUI

/// A race session on the Sports hub (Expo `SportsHubShowcase` race card and its
/// `FieldEventCard`): series and status, the weekend's title, "session · venue", how the session
/// stands, then the top two entries by position (three once final) with their timing. The same
/// size as a game card. Hide Scores keeps the schedule and drops the results.
struct SportsRaceCard: View {
    let listing: SportsRaceListing
    let leagueName: String
    let spoilers: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationLink(value: SportsRaceRef(weekendID: listing.weekend.id, sessionID: listing.session.id)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(leagueName.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    SportsStatusPill(lifecycle: listing.lifecycle)
                }
                .padding(.bottom, 2)
                Text(SportsRaceFormat.cardTitle(listing.weekend.title))
                    .font(.callout.weight(.semibold))
                    .lineLimit(rows.count > 2 ? 1 : 2)
                    .minimumScaleFactor(0.8)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(SportsRaceFormat.progress(session, spoilers: spoilers))
                    .font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if rows.isEmpty {
                    Text(SportsRaceFormat.cardEmpty(session, spoilers: spoilers)).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(rows) { driver in leaderRow(driver) }
                if session.stale {
                    Text("Updates delayed").font(.caption2).foregroundStyle(SportsStatusPill.amber)
                }
            }
            .padding(22)
            .frame(width: SportsGameCard.width, height: SportsGameCard.height, alignment: .topLeading)
            .background(Color.white.opacity(isFocused ? 0.16 : 0.08))
        }
        .buttonStyle(PosterFocusStyle(isFocused: isFocused))
        .focused($isFocused)
        .accessibilityIdentifier("sports-race-\(listing.key)")
    }

    private var session: SportsRaceEvent { listing.session }

    private var rows: [SportsRaceDriver] {
        spoilers || !(session.isLive || session.isFinal) ? [] : listing.leaders
    }

    private var subtitle: String {
        [SportsRaceDriver.filled(session.sessionType), session.place(listing.weekend)].compactMap { $0 }.joined(separator: " · ")
    }

    private func leaderRow(_ driver: SportsRaceDriver) -> some View {
        HStack(spacing: 12) {
            Text("\(driver.position ?? 0)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            Text(driver.name).font(.caption).lineLimit(1)
            Spacer(minLength: 8)
            if let value = SportsRaceFormat.cardValue(driver) {
                Text(value).font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Value pushed to open a race weekend's page on one of its sessions.
struct SportsRaceRef: Hashable {
    let weekendID: String
    let sessionID: String?
}
