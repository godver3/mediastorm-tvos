#if os(iOS)
import SwiftUI

/// The Expo mobile calendar's categories: the shared ones plus Upcoming and Recently Aired,
/// which narrow All to days from today on, or before it.
enum MobileCalendarCategory: String, CaseIterable, Identifiable {
    case all, upcoming, recent, tv, movies, watchlist, trending, top
    var id: Self { self }

    var label: String {
        switch self {
        case .upcoming: String(localized: "Upcoming")
        case .recent: String(localized: "Recently Aired")
        default: shared.label
        }
    }

    var symbol: String {
        switch self {
        case .all: "calendar"
        case .upcoming: "calendar.badge.clock"
        case .recent: "clock.arrow.circlepath"
        case .tv: "tv"
        case .movies: "film"
        case .watchlist: "bookmark"
        case .trending: "chart.line.uptrend.xyaxis"
        case .top: "star"
        }
    }

    var shared: CalendarCategory {
        switch self {
        case .all, .upcoming, .recent: .all
        case .tv: .tv
        case .movies: .movies
        case .watchlist: .watchlist
        case .trending: .trending
        case .top: .top
        }
    }

    func includes(_ day: CalendarDay, today: String) -> Bool {
        switch self {
        case .upcoming: day.key >= today
        case .recent: day.key < today
        default: true
        }
    }
}

/// Category chips and the strip of days, pinned over the agenda.
struct MobileCalendarControls: View {
    let days: [CalendarDay]
    @Binding var category: MobileCalendarCategory
    let selectedDay: String?
    let onDay: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MobileCalendarCategory.allCases) { entry in
                        let selected = entry == category
                        Button { category = entry } label: {
                            Label(entry.label, systemImage: entry.symbol).font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(selected ? .accentColor : .secondary)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("calendar-category-\(entry.rawValue)")
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
            if !days.isEmpty { dayStrip }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(days) { day in
                        let selected = day.key == selectedDay
                        let date = CalendarModel.date(fromKey: day.key)
                        Button { onDay(day.key) } label: {
                            VStack(spacing: 2) {
                                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.semibold))
                                Text(date.formatted(.dateTime.day())).font(.headline)
                                Circle().frame(width: 4, height: 4).opacity(0.8)
                            }
                            .frame(width: 44, height: 56)
                            .foregroundStyle(selected ? Color.white : .primary)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? Color.accentColor : Color.secondary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .id(day.key)
                        .accessibilityLabel(CalendarModel.fullDayHeading(day.key))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
            .onAppear { if let selectedDay { proxy.scrollTo(selectedDay, anchor: .center) } }
            .onChange(of: selectedDay) { _, key in
                guard let key else { return }
                withAnimation { proxy.scrollTo(key, anchor: .center) }
            }
        }
    }
}

/// "Today" over "Monday, November 8", with the day's release count.
struct MobileCalendarDayHeader: View {
    let day: CalendarDay

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(CalendarModel.dayHeading(day.key)).font(.headline).foregroundStyle(.primary)
                Text(CalendarModel.date(fromKey: day.key).formatted(.dateTime.month(.wide).day()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(CalendarModel.releaseCount(day.items.count)).font(.caption).foregroundStyle(.secondary)
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar-day-\(day.key)")
    }
}

/// One release: its poster, the time and source, the title, the episode and a summary.
struct MobileCalendarRow: View {
    let item: CalendarItem

    var body: some View {
        let target = DetailsTarget(item)
        NavigationLink(value: target) {
            HStack(alignment: .top, spacing: 12) {
                RemoteImage(url: Artwork.url(target.displayPosterURL, size: "w342"), size: CGSize(width: 64, height: 96)) { _ in
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 64, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(CalendarModel.formatTime(item.airTime)).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                        if let source = source {
                            Text(source).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(.quaternary))
                        }
                    }
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if let episode = item.episodeTitle, !episode.isEmpty {
                        Text(episode).font(.caption).lineLimit(1)
                    }
                    Text(CalendarModel.episodeLine(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(CalendarModel.summary(item)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .contextMenu { TitleActionsMenu(target: target, episode: CardEpisode(item)) }
        .accessibilityIdentifier("calendar-item-\(CalendarModel.itemKey(item))")
    }

    /// Expo's `formatSource`.
    private var source: String? {
        switch item.source {
        case "watchlist": String(localized: "Watchlist")
        case "history": String(localized: "History")
        case "top-trending": String(localized: "Top")
        case "mdblist": "MDBList"
        case "trending": String(localized: "Trending")
        default: nil
        }
    }
}
#endif
