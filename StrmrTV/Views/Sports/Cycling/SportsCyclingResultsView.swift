import SwiftUI

/// The results tabs (Expo `SportsCyclingDetailTV`'s results column): the stage's (or a team time
/// trial's team) classification, or the overall standings, with DNF / DNS / DSQ chips, 20 riders
/// a page, the leading three and the source line; beside a stage's results, the overall leaders
/// with View Overall Standings.
struct SportsCyclingResultsView: View {
    @ObservedObject var model: SportsCyclingPageModel
    let race: SportsCyclingRace
    let stage: SportsCyclingStage
    let viewOverall: () -> Void

    private enum Focus: Hashable { case chip(String), previous, next }
    @FocusState private var focus: Focus?

    var body: some View {
        let gc = stage.generalClassification
        if !race.oneDay && model.tab == .overview && !gc.rows.isEmpty {
            SportsColumns(weights: [1.6, 1]) {
                classification.frame(maxHeight: .infinity, alignment: .top).focusSection()
                SportsPanel(nil) {
                    SportsClassificationLeaders(
                        label: (gc.stale ? String(localized: "SAVED ") : "") + String(localized: "OVERALL GC · ")
                            + (stage.generalClassificationLabel ?? String(localized: "After \(stage.name)")),
                        entries: gc.rows, gapFirst: true)
                    Button("View Overall Standings", action: viewOverall).padding(.top, 8)
                        .accessibilityIdentifier("sports-cycling-view-overall")
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .focusSection()
            }
        } else {
            classification
        }
    }

    private var overall: Bool { model.tab == .overall }

    @ViewBuilder private var classification: some View {
        let rows = model.rows
        let teams = model.teamStage
        VStack(alignment: .leading, spacing: 20) {
            SportsSectionHeading(
                title: SportsCyclingFormat.resultsTitle(race, overall: overall, teams: teams),
                note: overall && !race.oneDay
                    ? (stage.generalClassificationLabel ?? String(localized: "After \(stage.name.lowercased())"))
                        + " · " + String(localized: "Overall race standings") : nil)
            if model.loading && rows.isEmpty {
                SportsNotice(title: String(localized: "Updating results"),
                             message: String(localized: "Loading the selected stage's published classifications."), loading: true)
            }
            if model.delayed {
                SportsNotice(title: String(localized: "Updates delayed"),
                             message: String(localized: "Displayed results may be incomplete or from an earlier update."),
                             retry: model.retry)
            }
            if rows.isEmpty && !model.loading && !model.failed {
                let notice = SportsCyclingFormat.emptyNotice(race, stage, model.classification)
                SportsNotice(title: notice.title, message: notice.message)
            }
            if !rows.isEmpty {
                if !model.resultStatuses.isEmpty { filterChips(teams: teams) }
                if model.pages > 1 { pager }
                table(teams: teams)
                if !stage.cancelled && model.activeFilter == nil {
                    SportsPanel(nil) {
                        SportsClassificationLeaders(
                            label: (model.classification?.stale == true ? String(localized: "Saved · ") : "")
                                + (overall && !race.oneDay ? String(localized: "GC Leaders") : String(localized: "Leading Finishers")),
                            entries: rows.filter { ($0.result ?? "").isEmpty }, gapFirst: false)
                    }
                }
            }
            if let source = SportsCyclingFormat.sourceLine(model.classification?.source) {
                Text(source).font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func filterChips(teams: Bool) -> some View {
        let chosen = model.activeFilter ?? ""
        return HStack(spacing: 18) {
            Button(teams ? "All Teams" : "All Riders") { model.filter(nil) }
                .buttonStyle(FilterChipStyle(selected: model.activeFilter == nil))
                .focused($focus, equals: .chip(""))
            ForEach(model.resultStatuses, id: \.self) { status in
                Button(status) { model.filter(status) }
                    .buttonStyle(FilterChipStyle(selected: model.activeFilter == status))
                    .focused($focus, equals: .chip(status))
            }
        }
        .font(.callout)
        .sportsChipRow()
        .defaultFocus($focus, .chip(chosen), priority: .userInitiated)
    }

    /// Previous / Next Riders and "2 / 8"; the pressed button hands focus to the other at either end.
    private var pager: some View {
        let page = model.currentPage
        return HStack(spacing: 24) {
            Button("Previous Riders") {
                model.page = page - 1
                if page - 1 == 0 { focus = .next }
            }
            .disabled(page == 0)
            .focused($focus, equals: .previous)
            Button("Next Riders") {
                model.page = page + 1
                if page + 1 == model.pages - 1 { focus = .previous }
            }
            .disabled(page >= model.pages - 1)
            .focused($focus, equals: .next)
            .accessibilityIdentifier("sports-cycling-next")
            Text("\(page + 1) / \(model.pages)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
        .sportsChipRow()
    }

    private func table(teams: Bool) -> some View {
        SportsPanel(nil, note: teams ? String(localized: "\(model.filtered.count) teams") : String(localized: "\(model.filtered.count) riders")) {
            HStack(spacing: 0) {
                SportsColumnHeading(String(localized: "Pos")).frame(width: 80)
                SportsColumnHeading(teams ? String(localized: "Team") : String(localized: "Rider / Team"))
                SportsColumnHeading(String(localized: "Time / Gap"), alignment: .trailing).frame(width: 220)
            }
            ForEach(model.visible) { row($0) }
        }
    }

    /// A rider's line: position (the winner's in accent), name, team · country · bib, DNF…, time over gap.
    private func row(_ result: SportsCyclingResult) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(result.rank.map(String.init) ?? "—").font(.title3.weight(.bold))
                .foregroundStyle(result.rank == 1 ? SportsStatusPill.accent : .secondary)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).font(.callout.weight(.semibold)).lineLimit(1)
                let line = SportsCyclingFormat.riderLine(result)
                if !line.isEmpty { Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if let status = result.result, !status.isEmpty {
                    Text(status).font(.caption.weight(.semibold)).foregroundStyle(SportsStatusPill.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                if let time = result.time { Text(time).font(.callout).monospacedDigit() }
                if let gap = result.gap { Text(gap).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                if result.time == nil && result.gap == nil { Text("—").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: 220, alignment: .trailing)
        }
        .sportsReadout()
    }
}

/// The top three of a classification (Expo `SportsClassificationLeaders`): reported positions
/// only, each a readout with its big position, name, team and time (the winner's) or gap.
struct SportsClassificationLeaders: View {
    let label: String
    let entries: [SportsCyclingResult]
    let gapFirst: Bool

    var body: some View {
        let leaders = entries.filter { (1...3).contains($0.rank ?? 0) }.sorted { $0.rank! < $1.rank! }
        if !leaders.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SportsEyebrow(text: label)
                ForEach(leaders) { leader in
                    HStack(spacing: 20) {
                        Text("\(leader.rank ?? 0)").font(.system(size: 44, weight: .bold)).foregroundStyle(SportsStatusPill.accent)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(leader.name).font(.callout.weight(.bold)).lineLimit(1)
                            if let team = leader.team, !team.isEmpty {
                                Text(team).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if let value = SportsCyclingFormat.leaderValue(leader, gapFirst: gapFirst) {
                            Text(value).font(.callout).monospacedDigit()
                        }
                    }
                    .sportsReadout()
                }
            }
        }
    }
}
