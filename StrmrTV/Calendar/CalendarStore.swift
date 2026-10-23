import Foundation

/// The Calendar screen's state, a port of the Expo `WideCalendarScreen` (TV branch) and
/// `useCalendarItemDetails`: the rail's category, the profile's calendar for its source,
/// the days it groups into, the focused release and the detail panel's metadata for it.
@MainActor
final class CalendarStore: ObservableObject {
    static let log = AppLog(category: "calendar")

    enum Phase: Equatable {
        case loading
        case failed(String)
        case loaded
    }

    @Published private(set) var category: CalendarCategory = .all
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var days: [CalendarDay] = []
    @Published private(set) var selection = CalendarSelection()
    @Published private(set) var detail: CalendarItemDetail?
    @Published private(set) var detailLoading = false

    private var items: [CalendarItem] = []
    private var loadTask: Task<Void, Never>?
    private var requestID = 0
    private var detailTask: Task<Void, Never>?
    /// Metadata by release, kept for the store's life (Expo keeps it for the screen's).
    private var enrichments: [String: CalendarEnrichment] = [:]
    /// When a release's metadata last failed; retried 30 s on.
    private var failures: [String: Date] = [:]

    /// Expo waits this long after focus settles before asking for a release's metadata.
    static let focusDebounce: Duration = .milliseconds(180)
    static let failureBackoff: TimeInterval = 30

    var activeItem: CalendarItem? {
        guard let key = selection.itemKey else { return nil }
        for day in days { if let item = day.items.first(where: { CalendarModel.itemKey($0) == key }) { return item } }
        return nil
    }

    var releaseTotal: Int { days.reduce(0) { $0 + $1.items.count } }

    // MARK: Loading

    /// Loads the calendar for the category's source. A newer load supersedes an older one.
    func load() {
        loadTask?.cancel()
        requestID += 1
        let request = requestID
        let source = category.source
        items = []
        days = []
        phase = .loading
        Self.log.info("load source=\(source.rawValue)")
        loadTask = Task {
            do {
                let items = try await APIClient.shared.calendar(source: source)
                guard request == requestID else { return }
                self.items = items
                phase = .loaded
                regroup()
                Self.log.info("loaded \(items.count) releases over \(days.count) days (source=\(source.rawValue))")
            } catch {
                guard request == requestID, !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
                selection = CalendarSelection()
                updateDetail()
                Self.log.error("load failed (source=\(source.rawValue)): \(error.localizedDescription)")
            }
        }
    }

    /// A rail category: a new filter and source, from the default selection.
    func choose(_ category: CalendarCategory) {
        guard category != self.category else { return }
        Self.log.info("category \(category.rawValue)")
        let reload = category.source != self.category.source
        self.category = category
        selection = CalendarSelection()
        if reload { load() } else { regroup() }
    }

    private func regroup() {
        let today = CalendarModel.dateKey(.now)
        // The Calendar tab has no Home view of its own, so Expo's `matchesHomeView` filter
        // is "all" here and keeps everything.
        days = CalendarModel.groupDays(items, filter: category.filter, todayKey: today)
        let resolved = CalendarModel.resolveSelection(days, dateKey: selection.dateKey, itemKey: selection.itemKey,
                                                      todayKey: today)
        if resolved != selection { selection = resolved }
        updateDetail()
    }

    // MARK: Focus

    /// A poster took focus: it becomes the selection and the detail panel's release.
    func preview(_ item: CalendarItem) {
        let next = CalendarSelection(dateKey: item.airDate, itemKey: CalendarModel.itemKey(item))
        guard next != selection else { return }
        selection = next
        updateDetail()
    }

    /// Shows the active release from the calendar at once, then its metadata once focus
    /// has rested on it (cached; a failure waits out the backoff before retrying).
    private func updateDetail() {
        detailTask?.cancel()
        guard let item = activeItem else {
            detail = nil
            detailLoading = false
            return
        }
        let key = cacheKey(item)
        let base = CalendarItemDetail(item)
        if let cached = enrichments[key] {
            detail = base.merged(cached)
            detailLoading = false
            return
        }
        detail = base
        detailLoading = false
        detailTask = Task { await fetchDetail(item, key: key) }
    }

    private func fetchDetail(_ item: CalendarItem, key: String) async {
        var delay = Self.focusDebounce
        if let failed = failures[key] {
            let remaining = Self.failureBackoff - Date.now.timeIntervalSince(failed)
            if remaining > 0 { delay += .milliseconds(Int(remaining * 1000)) }
        }
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        detailLoading = true
        do {
            let enrichment = try await APIClient.shared.calendarEnrichment(item)
            enrichments[key] = enrichment
            failures[key] = nil
            guard !Task.isCancelled, selection.itemKey == CalendarModel.itemKey(item) else { return }
            detail = CalendarItemDetail(item).merged(enrichment)
            detailLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            failures[key] = .now
            detailLoading = false
            Self.log.notice("details failed for \(item.titleID): \(error.localizedDescription)")
            // Retry after the backoff while the release is still the focused one.
            await fetchDetail(item, key: key)
        }
    }

    private func cacheKey(_ item: CalendarItem) -> String {
        "\(APIClient.shared.profileID)::\(CalendarModel.itemKey(item))"
    }
}
