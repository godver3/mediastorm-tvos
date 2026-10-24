import SwiftUI

/// What holds focus in the cycling page's controls.
enum SportsCyclingFocus: Hashable {
    case watch, stage, spoilers
    case tab(SportsCyclingTab)
}

/// The cycling page's top (Expo's editorial header and context row): "CYCLING", the race, the
/// stage's date, route, distance and terrain with its state, then Find Streams, the stage picker
/// (a menu of the race's stages) and Hide Scores, and the tabs (none while scores are hidden).
struct SportsCyclingHeader: View {
    @ObservedObject var model: SportsCyclingPageModel
    let race: SportsCyclingRace
    let spoilers: Bool
    let focus: FocusState<SportsCyclingFocus?>.Binding
    let watch: (SportsWatchTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(race.name).font(.system(size: 52, weight: .semibold)).lineLimit(2)
            if let stage = model.detail {
                HStack(alignment: .firstTextBaseline, spacing: 24) {
                    Text(SportsCyclingFormat.stageLine(stage)).font(.headline).lineLimit(1)
                    if !spoilers {
                        Text(SportsCyclingFormat.stageState(race, stage, model.classification))
                            .font(.callout.weight(.semibold)).foregroundStyle(SportsStatusPill.accent)
                    }
                }
            }
            controls.padding(.top, 18)
            if tabsShown { tabRow.padding(.top, 8) }
        }
    }

    /// Tabs show unless scores are hidden (a dates-only race keeps them: it has no scores).
    var tabsShown: Bool { !spoilers || race.scheduleOnly }

    /// Whether the race has stages to choose between.
    static func choosesStage(_ race: SportsCyclingRace) -> Bool { !race.oneDay && race.stages.count > 1 }

    private var eyebrow: String {
        [String(localized: "CYCLING"), race.captured ? String(localized: "RECORDED") : nil,
         model.delayed ? String(localized: "UPDATES DELAYED") : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private var controls: some View {
        HStack(spacing: 24) {
            if let target = model.watchTarget {
                Button { watch(target) } label: { Label("Find Streams", systemImage: "play.fill") }
                    .focused(focus, equals: .watch)
                    .accessibilityIdentifier("sports-cycling-watch")
            }
            if Self.choosesStage(race) {
                let noun = race.championship ? String(localized: "Race") : String(localized: "Stage")
                Menu {
                    Picker(noun, selection: Binding(get: { model.stage?.id ?? "" }, set: { model.select($0) })) {
                        ForEach(race.stages) { Text(SportsCyclingFormat.stageOption($0)).tag($0.id) }
                    }
                } label: {
                    Label("\(noun): \(model.stage?.name ?? String(localized: "Choose"))", systemImage: "chevron.down")
                }
                .focused(focus, equals: .stage)
                .accessibilityIdentifier("sports-cycling-stage")
            }
            Button { SportsSpoilers.shared.hidden.toggle() } label: {
                Label(spoilers ? "Show Scores" : "Hide Scores", systemImage: spoilers ? "eye" : "eye.slash")
            }
            .focused(focus, equals: .spoilers)
            .accessibilityIdentifier("sports-cycling-spoilers")
        }
        .sportsChipRow()
    }

    private var tabRow: some View {
        HStack(spacing: 18) {
            ForEach(model.tabs) { tab in
                Button(tab.label(race)) { model.show(tab) }
                    .buttonStyle(FilterChipStyle(selected: tab == model.tab))
                    .focused(focus, equals: .tab(tab))
                    .accessibilityIdentifier("sports-cycling-tab-\(tab.rawValue)")
            }
        }
        .font(.callout)
        .lineLimit(1)
        .sportsChipRow()
        .defaultFocus(focus, .tab(model.tab), priority: .userInitiated)
    }
}
