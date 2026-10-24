import SwiftUI

/// A cycling race's day on the Sports hub (Expo `SportsHubShowcase` cycling card, a
/// `FieldEventCard`): "CYCLING" and the day's state (REST DAY, SCHEDULE…), the race, the stage,
/// its distance and terrain (on a rest day "Racing resumes …"), then the stage's first two
/// finishers with their gaps once results are in. The same size as a game card. Hide Scores
/// drops the finishers.
struct SportsCyclingCard: View {
    let listing: SportsCyclingListing
    let spoilers: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        let rows = SportsCyclingFormat.cardRows(listing, spoilers: spoilers)
        NavigationLink(value: SportsCyclingRef(raceID: listing.race.id, stageID: listing.stage?.id)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(SportsCyclingFormat.cardLabel(listing.race).uppercased())
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    SportsTextPill(text: SportsCyclingFormat.cardPill(listing), amber: listing.lifecycle == .canceled)
                }
                .padding(.bottom, 2)
                Text(SportsRaceFormat.cardTitle(listing.race.name)).font(.callout.weight(.semibold)).lineLimit(2)
                    .minimumScaleFactor(0.8)
                let subtitle = SportsCyclingFormat.cardSubtitle(listing)
                if !subtitle.isEmpty { Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Text(SportsCyclingFormat.cardProgress(listing)).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if rows.isEmpty {
                    Text(SportsCyclingFormat.cardEmpty(listing, spoilers: spoilers)).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 12) {
                        Text("\(row.rank)").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .leading)
                        Text(row.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 8)
                        if let value = row.value {
                            Text(value).font(.caption2).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                if listing.stage?.results.stale == true { SportsCardDelayed() }
            }
            .padding(22)
            .frame(width: SportsGameCard.width, height: SportsGameCard.height, alignment: .topLeading)
            .background(Color.white.opacity(isFocused ? 0.16 : 0.08))
        }
        .buttonStyle(PosterFocusStyle(isFocused: isFocused))
        .focused($isFocused)
        .accessibilityIdentifier("sports-cycling-\(listing.key)")
    }
}

/// A status pill with its own text (cycling's REST DAY, SCHEDULE), amber for a schedule change.
struct SportsTextPill: View {
    let text: String
    var amber = false

    var body: some View {
        Text(text).font(.caption2.weight(.bold))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .foregroundStyle(amber ? SportsStatusPill.amber : .primary)
    }
}

/// Value pushed to open a cycling race's page, on one of its stages (nil: the default stage).
struct SportsCyclingRef: Hashable {
    let raceID: String
    let stageID: String?
}
