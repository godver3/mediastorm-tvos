import SwiftUI

/// The Route tab (Expo `SportsOrganizerGuide` for a stage): the organizer's route map and stage
/// profile (chips switch between them), Expand to see one full screen, the guide's state and
/// Retry Guide when it is late or missing. A calendar listing has its source only.
struct SportsCyclingRoute: View {
    @ObservedObject var model: SportsCyclingPageModel
    let race: SportsCyclingRace
    let stage: SportsCyclingStage

    @State private var chosen = 0
    @State private var expanded = false
    @FocusState private var chip: Int?

    /// Organizer paper, the colour the diagrams are drawn for.
    static let paper = Color(red: 0xF5 / 255, green: 0xF2 / 255, blue: 0xE9 / 255)

    private var guide: SportsCyclingRouteGuide? { stage.routeGuide }

    private var assets: [(label: String, url: URL)] {
        [(String(localized: "Route map"), guide?.mapUrl), (String(localized: "Stage profile"), guide?.profileUrl)]
            .compactMap { label, text in
                guard let text, text.hasPrefix("https://"), let url = URL(string: text) else { return nil }
                return (label, url)
            }
    }

    var body: some View {
        let assets = assets
        let asset = assets.indices.contains(chosen) ? assets[chosen] : assets.first
        let title = "\(race.name) · \(stage.name)"
        VStack(alignment: .leading, spacing: 20) {
            if guide?.state == "pending" && model.loading {
                SportsNotice(title: String(localized: "Loading stage guide"),
                             message: String(localized: "Checking the selected stage's official map and profile."), loading: true)
            }
            SportsPanel(nil) {
                VStack(alignment: .leading, spacing: 10) {
                    SportsEyebrow(text: guide != nil ? String(localized: "Official stage guide")
                                  : race.calendarOnly ? String(localized: "Calendar source") : String(localized: "Organizer race center"))
                    Text(title).font(.title3.weight(.semibold))
                    if !stage.route.isEmpty { Text(stage.route).foregroundStyle(.secondary) }
                    if guide?.state == "stale" {
                        Text("Updates delayed · Showing the last verified guide.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .sportsReadout()
                if assets.count > 1 { chips(assets.map(\.label)) }
                if let asset {
                    image(asset.url, size: CGSize(width: 1500, height: 420))
                } else {
                    Text(guide?.reason ?? (race.calendarOnly
                        ? String(localized: "This calendar supplies race dates only. Check the organizer for the published schedule.")
                        : String(localized: "Stage map and profile are unavailable here. The organizer guide may have further route details.")))
                        .foregroundStyle(.secondary).sportsReadout()
                }
                HStack(spacing: 24) {
                    if let asset {
                        Button(String(localized: "Expand \(asset.label)")) { expanded = true }
                            .accessibilityIdentifier("sports-cycling-expand")
                    }
                    if let guide, guide.state == "unavailable" || guide.state == "stale" {
                        Button("Retry Guide", action: model.retry)
                    }
                }
                .sportsChipRow()
            }
        }
        .onChange(of: stage.id) { chosen = 0 }
        .fullScreenCover(isPresented: $expanded) {
            if let asset {
                SportsMapCover(title: title, subtitle: [asset.label, stage.route].filter { !$0.isEmpty }.joined(separator: " · "),
                               note: String(localized: "Published organizer diagram"), close: { expanded = false }) {
                    image(asset.url, size: CGSize(width: 1680, height: 780))
                }
            }
        }
    }

    private func chips(_ labels: [String]) -> some View {
        HStack(spacing: 18) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                Button(label) { chosen = index }
                    .buttonStyle(FilterChipStyle(selected: index == chosen))
                    .focused($chip, equals: index)
            }
        }
        .font(.callout)
        .sportsChipRow()
        .defaultFocus($chip, chosen, priority: .userInitiated)
    }

    private func image(_ url: URL, size: CGSize) -> some View {
        RemoteImage(url: url, size: size, contentMode: .fit) { _ in
            Text("Guide image unavailable").font(.caption).foregroundStyle(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: size.height)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Self.paper))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
