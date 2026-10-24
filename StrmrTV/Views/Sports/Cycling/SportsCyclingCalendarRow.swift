import SwiftUI

/// A race of the cycling calendar (Expo `SportsCyclingHub`'s race card): when it runs and for
/// whom, a date stamp beside the name, the dates, the race's current stage on an organizer-paper
/// strip with its state, the stage winner, and what opening it offers. Select opens the race.
struct SportsCyclingCalendarRow: View {
    let race: SportsCyclingRace
    let today: String

    var body: some View {
        let stage = SportsCycling.defaultStage(race, today: today)
        let winner = stage.flatMap { stage in
            stage.cancelled || stage.results.state != "available" ? nil
                : stage.results.data.first { $0.rank == 1 && $0.result == nil }
        }
        NavigationLink(value: SportsCyclingRef(raceID: race.id, stageID: nil)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Text(SportsCycling.period(race, today: today).eyebrow
                         + (race.category == "unknown" ? String(localized: "ROAD RACE") : race.category.uppercased()))
                        .font(.caption.weight(.semibold)).kerning(1).foregroundStyle(.secondary)
                    if race.captured {
                        Text("CAPTURED RESULTS").font(.caption.weight(.semibold)).foregroundStyle(SportsStatusPill.accent)
                    }
                }
                HStack(spacing: 28) {
                    if let start = SportsCycling.dayStart(race.startDate ?? "") { stamp(start) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(race.name.uppercased()).font(.title2.weight(.semibold)).lineLimit(2)
                        Text(SportsCycling.dateRange(race)).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let stage { strip(stage) }
                if let winner, let stage {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(race.oneDay ? String(localized: "RACE WINNER") : String(localized: "\(stage.name.uppercased()) WINNER"))
                            .font(.caption2.weight(.semibold)).kerning(1).foregroundStyle(.secondary)
                        Text(winner.name).font(.headline)
                        let about = [winner.team, winner.time].compactMap { $0 }.joined(separator: " · ")
                        if !about.isEmpty { Text(about).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text(race.scheduleOnly ? String(localized: "Published schedule · Find streams →")
                     : (race.oneDay ? String(localized: "One-day race") : String(localized: "\(race.stages.count) stages available"))
                        + String(localized: " · View results & route guides →"))
                    .font(.callout).foregroundStyle(SportsStatusPill.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(SportsReadoutButtonStyle())
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
        .accessibilityIdentifier("sports-cycling-race-\(race.id)")
    }

    /// OCT / 1 / 2026.
    private func stamp(_ date: Date) -> some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.month(.abbreviated)).uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day())).font(.system(size: 44, weight: .bold))
            Text(date.formatted(.dateTime.year())).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 90)
    }

    /// The race's current stage on the organizer-paper strip: name, route, date · distance · terrain, its state.
    private func strip(_ stage: SportsCyclingStage) -> some View {
        let ink = Color(red: 0x53 / 255, green: 0x60 / 255, blue: 0x71 / 255)
        return HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.name).font(.caption.weight(.bold)).foregroundStyle(ink)
                if !stage.route.isEmpty {
                    Text(stage.route).font(.headline).foregroundStyle(Color(red: 0x17 / 255, green: 0x23 / 255, blue: 0x37 / 255))
                }
                Text([SportsCycling.date(stage.date), stage.distance, stage.terrain].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(SportsCyclingFormat.stripState(stage)).font(.caption).foregroundStyle(ink)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10).fill(SportsCyclingRoute.paper))
    }
}
