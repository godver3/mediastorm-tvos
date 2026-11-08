#if os(iOS)
import SwiftUI

/// The Calendar tab on a phone, a port of the Expo mobile calendar (`MobileCalendarScreen`)
/// on the shared `CalendarStore`: category chips (All, TV, Movies, Trending, Watchlist,
/// Top) and a strip of days over an agenda, a section per day. It opens on today (or the
/// next day with releases); tapping a day jumps to it. Tap a release for details; long
/// press for the title actions.
struct MobileCalendarView: View {
    @StateObject private var store = CalendarStore()
    @State private var started = false
    @State private var chosenDay: String?
    /// Releases on screen ("day|item"); the strip marks the first one's day.
    @State private var visibleRows: Set<String> = []
    @State private var category: MobileCalendarCategory = .all

    /// The store's days, narrowed for Upcoming / Recently Aired.
    private var days: [CalendarDay] {
        let today = CalendarModel.dateKey(.now)
        return store.days.filter { category.includes($0, today: today) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(days) { day in
                        Section {
                            ForEach(day.items, id: \.calendarKey) { item in
                                MobileCalendarRow(item: item)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .onScrollVisibilityChange(threshold: 0.3) { visible in
                                        let key = "\(day.key)|\(item.calendarKey)"
                                        if visible { visibleRows.insert(key) } else { visibleRows.remove(key) }
                                    }
                                    // A lazy row unloaded off screen reports no visibility change.
                                    .onDisappear { visibleRows.remove("\(day.key)|\(item.calendarKey)") }
                                Divider().padding(.leading, 92)
                            }
                        } header: {
                            MobileCalendarDayHeader(day: day)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(.background)
                        }
                        .id(day.key)
                    }
                }
                .padding(.bottom, 16)
            }
            .overlay { status }
            .safeAreaInset(edge: .top, spacing: 0) {
                MobileCalendarControls(days: days, category: $category, selectedDay: stripDay) { key in
                    chosenDay = key
                    withAnimation { proxy.scrollTo(key, anchor: .top) }
                }
            }
            .onChange(of: days) {
                chosenDay = nil
                visibleRows = []
                guard let key = selectedDay else { return }
                // After the list has laid the new days out.
                DispatchQueue.main.async { proxy.scrollTo(key, anchor: .top) }
            }
            .onChange(of: category) { _, category in store.choose(category.shared) }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text("Calendar").font(.headline)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .refreshable { store.load() }
        .task {
            guard !started else { return }
            started = true
            store.load()
        }
    }

    /// The day tapped in the strip, else the store's (today, or the next day with releases),
    /// else the first shown.
    private var selectedDay: String? {
        if let chosenDay, days.contains(where: { $0.key == chosenDay }) { return chosenDay }
        // Recently Aired opens on its latest day, the one nearest today.
        if category == .recent { return days.last?.key }
        if let key = store.selection.dateKey, days.contains(where: { $0.key == key }) { return key }
        return days.first?.key
    }

    /// The strip follows the agenda: the first day with a release on screen.
    private var stripDay: String? {
        let shown = Set(visibleRows.map { String($0.prefix { $0 != "|" }) })
        return days.first { shown.contains($0.key) }?.key ?? selectedDay
    }

    private var subtitle: String {
        let total = days.reduce(0) { $0 + $1.items.count }
        return total > 0
            ? String(localized: "\(total) releases across \(days.count) days")
            : String(localized: "Episodes and movies in one place")
    }

    @ViewBuilder
    private var status: some View {
        switch store.phase {
        case .loading:
            ProgressView("Loading your calendar…")
        case let .failed(message):
            ContentUnavailableView {
                Label("Calendar Unavailable", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { store.load() }.buttonStyle(.bordered)
            }
        case .loaded where days.isEmpty:
            ContentUnavailableView("Nothing Here Yet", systemImage: "calendar",
                                   description: Text("Try another category or enable more calendar sources for this profile."))
        case .loaded:
            EmptyView()
        }
    }
}
#endif
