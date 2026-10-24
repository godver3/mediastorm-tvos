import SwiftUI

/// What a screen's channel is airing, from the tiles' now / next.
struct MultiscreenProgramme {
    let current: EPGProgram?
    let next: EPGProgram?

    init(channel: LiveChannel?, nowNext: [String: EPGNowPlaying], at now: Date = Date()) {
        let entry = channel.flatMap { nowNext[$0.guideKey] }
        let airing = [entry?.current, entry?.next].compactMap { $0 }.first { $0.isAiring(at: now) }
        current = airing
        next = airing == entry?.next ? nil : entry?.next
    }

    /// "1 hr 5 min remaining".
    func remaining(at now: Date = Date()) -> String? {
        guard let current else { return nil }
        let minutes = Int((current.stop.timeIntervalSince(now) / 60).rounded(.up))
        if minutes >= 60 {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? String(localized: "\(hours) hr remaining") : String(localized: "\(hours) hr \(rest) min remaining")
        }
        return String(localized: "\(minutes) min remaining")
    }
}

/// A tile's caption over the bottom of its video: logo, what is on (or the channel), the
/// audible badge and the tile's status. Large tiles add the channel, stream info and time left.
struct MultiscreenTileOverlay: View {
    let slot: MultiscreenSlot
    let programme: MultiscreenProgramme
    let info: MultiscreenStreamInfo?
    let audible: Bool
    let width: CGFloat

    private var roomy: Bool { width >= 700 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                if let channel = slot.channel {
                    ChannelLogo(channel: channel, size: CGSize(width: roomy ? 56 : 40, height: roomy ? 56 : 40),
                                font: .caption, namesChannel: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(programme.current?.title ?? slot.channel?.name ?? String(localized: "Add channel"))
                        .font(roomy ? .headline : .caption.weight(.semibold))
                        .lineLimit(1)
                    if roomy, let detail {
                        Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if audible, slot.channel != nil {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(roomy ? .callout : .caption)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Playing audio")
                }
            }
            if let status = MultiscreenTileOverlay.status(slot) {
                Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(roomy ? 20 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.82), .black.opacity(0.95)], startPoint: .top, endPoint: .bottom)
        )
    }

    private var detail: String? {
        // Without guide data the title is already the channel's name.
        let name = programme.current == nil ? nil : slot.channel?.name
        let parts = [name, info?.label, programme.remaining()].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Tuning…" or the slot's error.
    static func status(_ slot: MultiscreenSlot) -> String? {
        slot.loading ? String(localized: "Tuning…") : slot.error
    }
}

/// The control bar's left side: the focused screen in full.
struct MultiscreenDockDetails: View {
    let slot: MultiscreenSlot
    let programme: MultiscreenProgramme
    let info: MultiscreenStreamInfo?
    let audible: Bool
    let status: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if let channel = slot.channel {
                    ChannelLogo(channel: channel, size: CGSize(width: 72, height: 56), font: .caption, namesChannel: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(programme.current?.title ?? slot.channel?.name ?? String(localized: "Add channel"))
                        .font(.headline).lineLimit(1)
                    let meta = [slot.channel?.name, info?.label].compactMap { $0 }.joined(separator: " · ")
                    if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                if audible, slot.channel != nil {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Color.accentColor)
                }
            }
            if let description = programme.current?.description, !description.isEmpty {
                Text(description).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let status { Text(status).font(.caption).foregroundStyle(.red).lineLimit(2) }
            if let current = programme.current {
                ProgressBar(fraction: current.progress(at: now)).frame(maxWidth: 560)
                HStack(spacing: 16) {
                    if let remaining = programme.remaining(at: now) { Text(remaining) }
                    if let next = programme.next {
                        Text("Next: \(next.title) at \(next.start.formatted(.dateTime.hour().minute()))").lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
