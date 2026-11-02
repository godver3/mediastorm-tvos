import SwiftUI

/// The focused programme: title, times, time left, episode and description, with its channel.
struct GuideInfoPanel: View {
    let channel: LiveChannel?
    let program: EPGProgram?
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 10) {
                Text(program?.title ?? channel?.name ?? "")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                if let program {
                    HStack(spacing: 16) {
                        if program.isAiring(at: now) {
                            Text("LIVE")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(.red))
                        }
                        if channel?.canReplay(program, now: now) == true {
                            Label(program.stop <= now ? "Catch-up" : "Start Over", systemImage: "gobackward")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(.white.opacity(0.18)))
                                .foregroundStyle(.white)
                        }
                        Text(details(program))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let description = program.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .frame(maxWidth: 1100, alignment: .leading)
                    }
                } else if let channel {
                    Text(channel.group ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let channel {
                VStack(alignment: .trailing, spacing: 8) {
                    ChannelLogo(channel: channel, size: CGSize(width: 220, height: 110), font: .largeTitle, namesChannel: false)
                    Text(channel.name).font(.caption.weight(.semibold)).lineLimit(1)
                    if let group = channel.group { Text(group).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(width: 320, alignment: .trailing)
            }
        }
    }

    private func details(_ p: EPGProgram) -> String {
        var parts = [GuideTime.range(p.start, p.stop)]
        if p.isAiring(at: now) {
            let left = Int(p.stop.timeIntervalSince(now) / 60)
            parts.append(String(localized: "\(left) min left"))
        } else if p.start > now || p.stop <= now {
            parts.append(p.start.formatted(.relative(presentation: .named)))
        }
        if let ep = p.episode, !ep.isEmpty { parts.append(ep) }
        if let cat = p.categories?.first { parts.append(cat) }
        return parts.joined(separator: " · ")
    }
}

enum GuideTime {
    static func range(_ start: Date, _ end: Date) -> String {
        let f = Date.FormatStyle.dateTime.hour().minute()
        let range = "\(start.formatted(f))–\(end.formatted(f))"
        // Catch-up pages back days: name the day when it isn't today.
        guard !Calendar.current.isDateInToday(start) else { return range }
        return "\(start.formatted(.dateTime.weekday(.abbreviated))) \(range)"
    }
}
