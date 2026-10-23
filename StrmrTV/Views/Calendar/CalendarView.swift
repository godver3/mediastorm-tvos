import SwiftUI

/// What can hold focus on the Calendar screen.
enum CalendarFocus: Hashable {
    case rail(CalendarCategory)
    /// A poster, by `CalendarModel.itemKey`.
    case poster(String)
    case retry
}

/// The Calendar tab, a port of the Expo TV Calendar (`WideCalendarScreen`): the category
/// rail on the left; the month timeline over the feed of days, each a row of posters; and
/// the focused release's detail panel down the right. Focus drives the selection: the
/// focused poster's day is centred in the feed and marked on the timeline. Select opens
/// details; long press offers the title actions.
struct CalendarView: View {
    @StateObject private var store = CalendarStore()
    @FocusState private var focus: CalendarFocus?
    /// The poster last focused in each day, where Up / Down re-enters that day's row.
    @State private var remembered: [String: String] = [:]
    @State private var started = false

    static let railWidth: CGFloat = 320
    static let panelWidth: CGFloat = 550
    /// The feed and timeline stop short of the panel's opaque part (Expo's preview reservation).
    static let panelReservation: CGFloat = 512
    /// Expo's default accent (`accent.primary`, #3f66ff): the rail's selection and the
    /// timeline marker. The app has no accent theming yet, and its tint is white.
    static let accent = Color(red: 0x3f / 255, green: 0x66 / 255, blue: 1)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 0) {
                rail
                    .frame(width: Self.railWidth, alignment: .topLeading)
                    .focusSection()
                    // Left from the feed lands on the chosen category, not the nearest one.
                    .defaultFocus($focus, .rail(store.category), priority: .userInitiated)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if store.phase == .loaded, !store.days.isEmpty {
                CalendarDetailPanel(detail: store.detail, loading: store.detailLoading)
                    .frame(width: Self.panelWidth)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(edges: [.trailing, .bottom])
                    .allowsHitTesting(false)
            }
        }
        .defaultFocus($focus, .rail(store.category))
        .onChange(of: focus) { old, new in
            guard case let .poster(key)? = new, let item = item(key) else { return }
            // Right from the rail goes to the selected release (Expo's focus destination),
            // not to whichever poster is nearest, which may be a day half under the timeline.
            if case .rail? = old, let active = store.selection.itemKey, active != key, self.item(active) != nil {
                focus = .poster(active)
                return
            }
            remembered[item.airDate] = key
            store.preview(item)
        }
        // Once per visit of the tab: coming back from details keeps the feed as it was.
        .task {
            guard !started else { return }
            started = true
            store.load()
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Calendar")
                .font(.system(size: 50, weight: .medium))
                .padding(.bottom, 20)
                .padding(.leading, 14)
            ForEach(CalendarCategory.allCases) { category in
                CalendarRailButton(label: category.label, selected: store.category == category,
                                   focused: focus == .rail(category)) {
                    remembered = [:]
                    store.choose(category)
                }
                .focused($focus, equals: .rail(category))
                .accessibilityIdentifier("calendar-nav-\(category.rawValue)")
            }
        }
        .padding(.leading, 46)
        .padding(.trailing, 20)
        .padding(.top, 20)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            CalendarStateView(symbol: nil, title: nil, message: String(localized: "Loading calendar..."), loading: true)
        case let .failed(message):
            CalendarStateView(symbol: "exclamationmark.triangle", title: String(localized: "Calendar unavailable"),
                              message: message) {
                Button("Try again") { store.load() }
                    .focused($focus, equals: .retry)
                    .accessibilityIdentifier("calendar-state-retry")
            }
        case .loaded where store.days.isEmpty:
            CalendarStateView(symbol: "calendar", title: String(localized: "No calendar items"),
                              message: String(localized: "Try another filter or enable more calendar sources for this profile."))
                // Something focusable, so focus can come back from the rail and the tab bar.
                .focusable()
        case .loaded:
            browser
        }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 16) {
            CalendarTimelineView(days: store.days, activeDateKey: store.selection.dateKey)
                .frame(height: 93)
                .padding(.vertical, 12)
                .padding(.trailing, Self.panelReservation)
            CalendarFeed(days: store.days, selection: store.selection, focus: $focus, remembered: remembered)
                .padding(.trailing, Self.panelReservation)
                .focusSection()
                .defaultFocus($focus, store.selection.itemKey.map(CalendarFocus.poster), priority: .userInitiated)
        }
        .padding(.leading, 22)
        .padding(.top, 8)
    }

    private func item(_ key: String) -> CalendarItem? {
        for day in store.days { if let item = day.items.first(where: { CalendarModel.itemKey($0) == key }) { return item } }
        return nil
    }
}

/// A rail category: the selected one in the accent colour with a bar on its left, the
/// focused one dark on white (Expo's `CalendarNavigationItem`).
private struct CalendarRailButton: View {
    let label: String
    let selected: Bool
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(focused ? Color(white: 0.07) : selected ? CalendarView.accent : Color.primary)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4).fill(focused ? Color(white: 0.96) : .clear))
                .overlay(alignment: .leading) {
                    if selected { Rectangle().fill(CalendarView.accent).frame(width: 4) }
                }
        }
        .buttonStyle(CalendarPlainButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// No system highlight: the view draws its own focus.
struct CalendarPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Loading, error and empty states (`CalendarState`).
private struct CalendarStateView<Action: View>: View {
    let symbol: String?
    let title: String?
    let message: String
    var loading = false
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 18) {
            if loading { ProgressView() }
            if let symbol { Image(systemName: symbol).font(.system(size: 56)).foregroundStyle(.secondary) }
            if let title { Text(title).font(.title3.weight(.bold)) }
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 900)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-state")
    }
}

extension CalendarStateView where Action == EmptyView {
    init(symbol: String?, title: String?, message: String, loading: Bool = false) {
        self.init(symbol: symbol, title: title, message: message, loading: loading) { EmptyView() }
    }
}
