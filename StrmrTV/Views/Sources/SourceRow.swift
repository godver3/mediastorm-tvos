import SwiftUI

/// One source: health and quality badges, the release name, then size / provider / audio.
/// The details page's source picker and the player's Switch Source list.
struct SourceRow: View {
    let result: SourceResult
    let health: SourceHealth?
    /// Tracks were picked for this source with a long press.
    var hasTrackPicks = false
    /// The source playing now (the player's Switch Source list).
    var isCurrent = false

    private var attrs: [String: String] { result.attributes }

    /// Release name: the first line of the scraper's raw title when present.
    private var releaseName: String {
        (attrs["raw_title"] ?? result.title).components(separatedBy: "\n").first ?? result.title
    }

    private var badges: [String] {
        var out: [String] = []
        if let res = attrs["resolution"], !res.isEmpty { out.append(res == "2160p" ? "4K" : res) }
        if attrs["hasDV"] == "true" { out.append("DV") }
        if let hdr = attrs["hdr"], hdr.contains("HDR10+") { out.append("HDR10+") } else if let hdr = attrs["hdr"], hdr.contains("HDR") { out.append("HDR") }
        if let quality = attrs["quality"], !quality.isEmpty { out.append(quality) }
        if let codec = attrs["codec"], !codec.isEmpty { out.append(codec.uppercased()) }
        return out
    }

    private var details: String {
        var parts: [String] = []
        if result.sizeBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file))
        }
        parts.append(result.serviceType == "usenet" ? "Usenet" : (attrs["tracker"] ?? result.indexer))
        if let seeders = attrs["seeders"], !seeders.isEmpty, result.serviceType != "usenet" { parts.append("\(seeders) seeders") }
        if let audio = attrs["audio"], !audio.isEmpty { parts.append(audio) }
        if let channels = attrs["channels"], !channels.isEmpty { parts.append(channels) }
        if let languages = attrs["languages"], !languages.isEmpty {
            parts.append(languages.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "⚙", with: "").trimmingCharacters(in: .whitespaces))
        }
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isCurrent {
                    Label("Playing", systemImage: "checkmark.circle.fill").font(.caption2.weight(.bold))
                }
                if let health { HealthBadge(health: health) }
                if hasTrackPicks {
                    Label("Tracks chosen", systemImage: "waveform").font(.caption2.weight(.bold))
                }
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, lineWidth: 1.5))
                }
            }
            Text(releaseName).font(.callout).lineLimit(1)
            Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 8)
    }
}

/// Debrid cache / usenet health: green when playable, red when not, spinner while checking.
private struct HealthBadge: View {
    let health: SourceHealth

    var body: some View {
        switch health.state {
        case "pending":
            ProgressView().scaleEffect(0.5).frame(width: 28, height: 28)
                .accessibilityLabel("Checking availability")
        case "healthy", "cached", "unhealthy", "not_cached":
            let good = health.state == "healthy" || health.state == "cached"
            Label(label, systemImage: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(good ? .green : .red)
        default:
            EmptyView()
        }
    }

    private var label: String {
        switch health.state {
        case "cached": "Cached"
        case "not_cached": "Not Cached"
        case "healthy": "Healthy"
        default: "Unhealthy"
        }
    }
}
