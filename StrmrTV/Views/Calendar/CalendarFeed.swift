import SwiftUI

/// The days, top to bottom, each a heading and a row of posters (`CalendarReleaseFeed`'s
/// TV list). The selected day is kept centred, as Expo's list snaps its day to the centre.
struct CalendarFeed: View {
    let days: [CalendarDay]
    let selection: CalendarSelection
    var focus: FocusState<CalendarFocus?>.Binding
    let remembered: [String: String]

    @State private var placed = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(days) { day in
                        CalendarDayRow(day: day, focus: focus,
                                       entry: remembered[day.key] ?? day.items.first.map(CalendarModel.itemKey))
                            .id(day.key)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            // The days scroll under the timeline's edge, not over it (Expo's viewport clips).
            .clipped()
            // Opens on the selected day (today's, or the next with releases), centred.
            .onAppear {
                guard !placed, let key = selection.dateKey else { return }
                placed = true
                proxy.scrollTo(key, anchor: .center)
            }
            .onChange(of: selection.dateKey) { _, key in
                guard let key else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(key, anchor: .center) }
            }
        }
    }
}

/// One day: "Monday, October 20 ——— 3 releases" over its posters (`CalendarDaySection`).
struct CalendarDayRow: View {
    let day: CalendarDay
    var focus: FocusState<CalendarFocus?>.Binding
    /// The poster Up / Down lands on: the one last focused in this day, else the first.
    let entry: String?

    static let posterWidth: CGFloat = 210
    static let posterHeight: CGFloat = 315
    /// Room around the posters inside the row for the focus lift and its shadow.
    static let liftRoom: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Text(CalendarModel.fullDayHeading(day.key))
                    .font(.system(size: 34, weight: .heavy))
                    .lineLimit(1)
                    .layoutPriority(1)
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1).frame(minWidth: 32)
                Text(CalendarModel.releaseCount(day.items.count))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 32)
            }
            .padding(.horizontal, Self.liftRoom)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("calendar-day-\(day.key)")

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 26) {
                    ForEach(day.items, id: \.calendarKey) { item in
                        CalendarPosterCard(item: item, focus: focus)
                    }
                }
                .padding(.vertical, Self.liftRoom)
            }
            .contentMargins(.horizontal, Self.liftRoom, for: .scrollContent)
            .scrollIndicators(.hidden)
            .focusSection()
            .defaultFocus(focus, entry.map(CalendarFocus.poster), priority: .userInitiated)
        }
        .padding(.bottom, 14)
    }
}

/// A release's poster with its title and "S01E04" (or the movie's release type) under it
/// (`CalendarPosterCard`), in the app's card focus style (1.06 lift and hairline).
struct CalendarPosterCard: View {
    let item: CalendarItem
    var focus: FocusState<CalendarFocus?>.Binding

    private var key: String { CalendarModel.itemKey(item) }
    private var isFocused: Bool { focus.wrappedValue == .poster(key) }

    var body: some View {
        let target = DetailsTarget(item)
        let width = CalendarDayRow.posterWidth, height = CalendarDayRow.posterHeight
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: height)) {
            NavigationLink(value: target) {
                RemoteImage(url: Artwork.url(target.displayPosterURL, size: "w500"), size: CGSize(width: width, height: height)) { _ in
                    Rectangle().fill(.quaternary)
                        .overlay(Text(item.title).font(.caption).multilineTextAlignment(.center).padding())
                }
            }
            .buttonStyle(PosterFocusStyle(isFocused: isFocused))
            .focused(focus, equals: .poster(key))
            .contextMenu { TitleActionsMenu(target: target, episode: CardEpisode(item)) }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier("calendar-poster-\(key)")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 24, weight: .bold)).lineLimit(1)
                let metadata = CalendarModel.posterMetadata(item)
                if !metadata.isEmpty {
                    Text(metadata).font(.system(size: 21)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(height: 64, alignment: .top)
        }
        .frame(width: width, alignment: .leading)
    }

    private var accessibilityLabel: String {
        let metadata = CalendarModel.posterMetadata(item)
        return metadata.isEmpty ? item.title : "\(item.title), \(metadata)"
    }
}
