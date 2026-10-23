import SwiftUI

/// The month timeline over the feed (`CalendarDateTimeline`): month labels and dots on a
/// line that slides so the selected day sits under a fixed marker 28% across.
struct CalendarTimelineView: View {
    let days: [CalendarDay]
    let activeDateKey: String?

    static let monthSpacing: CGFloat = 400
    static let markerPosition: CGFloat = 0.28
    private static let lineY: CGFloat = 53

    @State private var animates = false

    var body: some View {
        let timeline = CalendarTimeline(days: days, spacing: Self.monthSpacing)
        GeometryReader { geometry in
            if let activeDateKey, days.contains(where: { $0.key == activeDateKey }) {
                let offset = geometry.size.width * Self.markerPosition - timeline.position(of: activeDateKey)
                ZStack(alignment: .topLeading) {
                    track(timeline)
                        .offset(x: offset)
                        .animation(animates ? .easeOut(duration: 0.36) : nil, value: offset)
                    marker(activeDateKey, days: days)
                        .position(x: geometry.size.width * Self.markerPosition, y: Self.lineY + 18)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .clipped()
                // The first placement is instant; later moves slide.
                .task { animates = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("calendar-date-timeline")
    }

    private func track(_ timeline: CalendarTimeline) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0x24 / 255, green: 0x43 / 255, blue: 0x5c / 255))
                .frame(width: timeline.width, height: 1)
                .offset(y: Self.lineY)
            ForEach(Array(timeline.months.enumerated()), id: \.element.id) { index, month in
                VStack(spacing: 13) {
                    Text(month.label)
                        .font(.system(size: 21, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(Color(red: 0x71 / 255, green: 0x87 / 255, blue: 0xa1 / 255))
                        .fixedSize()
                    Circle().fill(Color(red: 0x17 / 255, green: 0x3f / 255, blue: 0x62 / 255)).frame(width: 6, height: 6)
                }
                .frame(width: 80)
                .offset(x: CGFloat(index) * timeline.spacing - 40, y: 13)
            }
        }
        .frame(width: timeline.width, alignment: .topLeading)
    }

    private func marker(_ key: String, days: [CalendarDay]) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(CalendarView.accent)
                .overlay(Circle().strokeBorder(Color(red: 0xdb / 255, green: 0xe9 / 255, blue: 1), lineWidth: 2))
                .frame(width: 16, height: 16)
            Text(CalendarModel.markerLabel(key))
                .font(.system(size: 27, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Color(red: 0xf4 / 255, green: 0xf8 / 255, blue: 0xfc / 255))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var accessibilityLabel: String {
        guard let activeDateKey, let day = days.first(where: { $0.key == activeDateKey }) else { return "" }
        let date = CalendarModel.date(fromKey: activeDateKey).formatted(.dateTime.weekday(.wide).month(.wide).day())
        return "\(date), \(CalendarModel.releaseCount(day.items.count))"
    }
}
