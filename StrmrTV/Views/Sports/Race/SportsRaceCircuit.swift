import SwiftUI

/// A weekend's circuit (Expo `SportsCircuitMap`): community reference geometry drawn north up,
/// its length and attribution; Expand Map shows it full screen. Never live positions.
struct SportsCircuitMap: View {
    let circuit: SportsCircuit

    @State private var expanded = false

    var body: some View {
        if let outline = circuit.outline() {
            let length = circuit.referenceLengthMeters > 0 ? SportsRaceFormat.kilometres(circuit.referenceLengthMeters) : nil
            SportsPanel(nil) {
                VStack(alignment: .leading, spacing: 8) {
                    SportsEyebrow(text: String(localized: "Circuit guide"))
                    Text(circuit.name).font(.headline)
                    Text([circuit.location.isEmpty ? nil : circuit.location, String(localized: "Reference layout")]
                        .compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    SportsCircuitOutlineView(outline: outline)
                        .frame(height: 260)
                        .overlay(alignment: .topTrailing) {
                            Text("N ↑").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    if let length { Text("\(length) · Reference length").font(.callout.weight(.semibold)) }
                    Text("Community reference geometry. This event's configuration may differ. Live car positions and telemetry are not connected.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if !circuit.attribution.isEmpty { Text(circuit.attribution).font(.caption2).foregroundStyle(.tertiary) }
                }
                .sportsReadout()
                Button("Expand Map") { expanded = true }
                    .font(.caption)
                    .accessibilityIdentifier("sports-race-expand-map")
            }
            .fullScreenCover(isPresented: $expanded) {
                SportsMapCover(
                    title: circuit.name,
                    subtitle: [circuit.location.isEmpty ? nil : circuit.location, String(localized: "North is up"),
                               length.map { String(localized: "\($0) reference length") }].compactMap { $0 }.joined(separator: " · "),
                    note: String(localized: "Reference layout; event configuration may differ. No live positions, sector boundaries or corner labels are supplied."),
                    close: { expanded = false }
                ) {
                    SportsCircuitOutlineView(outline: outline, lineWidth: 6)
                }
            }
        }
    }
}

/// A circuit map full screen, with a note under it; Close Map or Menu closes it.
struct SportsMapCover<Map: View>: View {
    let title: String
    let subtitle: String
    let note: String
    let close: () -> Void
    @ViewBuilder let map: Map

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
            map.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(note).font(.caption).foregroundStyle(.secondary)
            Button("Close Map", action: close).accessibilityIdentifier("sports-race-close-map")
        }
        .padding(.horizontal, 120)
        .padding(.vertical, 60)
        .background { SourcePickerBackdrop(url: nil) }
    }
}

/// The outline scaled to fit and centred: a wide dim track under a thin accent line (Expo's two
/// polylines).
struct SportsCircuitOutlineView: View {
    let outline: SportsCircuitOutline
    var lineWidth: CGFloat = 4

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 20
            let scale = min((size.width - 2 * inset) / outline.width, (size.height - 2 * inset) / outline.height)
            let left = (size.width - outline.width * scale) / 2, top = (size.height - outline.height * scale) / 2
            var path = Path()
            for (index, point) in outline.points.enumerated() {
                let p = CGPoint(x: left + point.x * scale, y: top + point.y * scale)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            let style = { (width: CGFloat) in StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
            context.stroke(path, with: .color(.white.opacity(0.16)), style: style(lineWidth * 3.2))
            context.stroke(path, with: .color(SportsStatusPill.accent), style: style(lineWidth))
        }
        .accessibilityLabel("Circuit outline")
    }
}

/// The organizer's guide to a MotoGP circuit (Expo `SportsMotoGPCircuit` in its
/// `SportsOrganizerGuide`): the published diagram, then length, corners and the longest
/// straight; a notice while it loads or when it can't.
struct SportsMotoGPGuide: View {
    let guide: SportsMotoGPEnrichment?
    let failed: Bool
    let venue: String?
    let retry: () -> Void

    @State private var expanded = false

    var body: some View {
        if let guide {
            panel(guide)
        } else {
            SportsNotice(title: failed ? String(localized: "Circuit guide unavailable") : String(localized: "Loading circuit guide"),
                         message: failed ? String(localized: "Session results remain available. Try the circuit guide again.")
                             : String(localized: "Fetching the organizer's circuit information."),
                         loading: !failed, retry: failed ? retry : nil)
        }
    }

    private func panel(_ guide: SportsMotoGPEnrichment) -> some View {
        let circuit = guide.circuit
        let name = circuit?.name ?? venue ?? String(localized: "Circuit guide")
        let about = [guide.season.map { String(localized: "\(String($0)) event") }, String(localized: "Official static diagram")]
            .compactMap { $0 }.joined(separator: " · ")
        let facts = circuit.map { c in
            [c.lengthMeters.map(SportsRaceFormat.kilometres), c.leftCorners.map { String(localized: "\($0) left corners") },
             c.rightCorners.map { String(localized: "\($0) right corners") },
             c.longestStraightMeters.map { String(localized: "\($0) m longest straight") }].compactMap { $0 }
        } ?? []
        return SportsPanel(nil) {
            VStack(alignment: .leading, spacing: 8) {
                SportsEyebrow(text: String(localized: "Organizer guide"))
                Text(name).font(.headline)
                Text(about).font(.caption).foregroundStyle(.secondary)
                if guide.stale {
                    Text("Updates delayed · Showing the last verified guide.").font(.caption).foregroundStyle(SportsStatusPill.amber)
                }
                if let map = circuit?.map {
                    diagram(map, size: CGSize(width: 640, height: 260))
                } else {
                    Text(guide.reason ?? String(localized: "An inline diagram is not available for this selection."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.callout) }
                if circuit?.map != nil {
                    Text("Published circuit guide · No live positions").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .sportsReadout()
            HStack(spacing: 20) {
                if circuit?.map != nil {
                    Button("Expand Map") { expanded = true }.accessibilityIdentifier("sports-race-expand-map")
                }
                if guide.state != "available" { Button("Retry Guide", action: retry) }
            }
            .font(.caption)
        }
        .fullScreenCover(isPresented: $expanded) {
            if let map = circuit?.map {
                SportsMapCover(title: name, subtitle: about, note: String(localized: "Published circuit guide · No live positions"),
                               close: { expanded = false }) { diagram(map, size: CGSize(width: 1600, height: 760)) }
            }
        }
    }

    private func diagram(_ url: URL, size: CGSize) -> some View {
        RemoteImage(url: url, size: size, contentMode: .fit) { _ in
            Text("Guide image unavailable").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
