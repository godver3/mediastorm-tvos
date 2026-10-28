import Combine
import Foundation

/// Home's rows, built from the profile's `homeShelves` config: every enabled shelf the
/// app knows, in the configured order, each loaded from its own source. Rows that come
/// back empty are left out, as on the Expo TV home; a row still loading, or that failed
/// with nothing to show, keeps its place as a placeholder (`slots`). One store per Home
/// view (`HomeViewsStore.store(for:)`), laid out as that view resolves.
@MainActor
final class HomeStore: ObservableObject {
    private static let log = AppLog(category: "home")

    /// The Home view this store shows (`all` for Home itself).
    let view: String
    /// A load has finished: showing the store again only needs a staleness check.
    var hasLoaded: Bool { settings != nil }

    /// The rows with cards, in order: what focus can move through.
    @Published private(set) var shelves: [HomeShelf] = []
    /// What Home lays out: the rows with cards and, between them, placeholders for rows
    /// still loading or that failed.
    @Published private(set) var slots: [HomeSlot] = []
    @Published private(set) var isLoading = true
    @Published private(set) var loadError: String?
    /// Where focus was on the page when it last left the screen (see `HomeFocusMemory`).
    var focusMemory: HomeFocusMemory?

    /// The watchlist row comes from the shared `WatchlistStore`, set by the view.
    var watchlist: [WatchlistItem] = [] {
        didSet {
            guard watchlist != oldValue else { return }
            rebuildWatchlist()
            writeTopShelf()
        }
    }

    /// The view's Watchlist row, if it has one: the row a title leaves when it is
    /// removed from the watchlist.
    var watchlistShelfID: String? { plan.first { $0.source == .watchlist }?.id }

    /// Continue Watching as last fetched, for the Top Shelf; nil until the first load.
    private var topShelfContinue: [ContinueWatchingItem]?

    private var settings: HomeSettings?
    private var plan: [PlannedShelf] = []
    private var rows: [String: HomeShelf] = [:]
    /// The manifest revision of the last full load; a different one means reload.
    private var revision: String?
    private var loadGeneration = 0
    /// Full loads and staleness checks running. Returning from the player fires `.task`,
    /// the cover change and the scene phase together: the first checks, the rest skip.
    private var loadsRunning = 0
    private var checksRunning = 0
    /// Rows are published as they arrive once the page has been revealed.
    private var revealed = false
    /// A first load's `revealAfter` has passed; it reveals once the top row is ready.
    private var revealDue = false
    /// Rows being fetched that have nothing to show yet.
    private var loading: Set<String> = []
    /// Rows whose last fetch failed with nothing to show, retried on the next refresh.
    private var failed: Set<String> = []
    /// Second passes filling in progressive rows (`ShelfPhase.complete`), by row.
    private var completions: [String: Task<Void, Never>] = [:]
    /// Calendar rows waiting on a server calendar still being built: they keep loading and retry.
    private var calendarPending: Set<String> = []
    private var calendarRetries = 0
    private var calendarRetry: Task<Void, Never>?

    /// A first load shows nothing until every row is in, or this long has passed and the
    /// top row has its cards, so rows that answer at once (or come back empty) never flash
    /// a placeholder and the page never opens on placeholders alone. After that, a slow
    /// row holds its place with a placeholder, so nothing moves when it arrives.
    private static let revealAfter: Duration = .seconds(1)

    /// Re-publishes when the top menu changes: Watch Something's Search card goes with
    /// the Search tab.
    private var menuChanges: AnyCancellable?
    /// Re-publishes when rows are hidden or shown in Settings.
    private var hiddenChanges: AnyCancellable?

    init(view: String = HomeViews.all) {
        self.view = view
        let menu = MenuTabsStore.shared
        menuChanges = menu.$overrides.combineLatest(menu.$profileTabs)
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in self?.publish() } }
        hiddenChanges = HomeLayoutStore.shared.$hiddenShelves
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor in self?.publish() } }
    }

    // MARK: Loading

    /// Reloads the config and every row. Rows already shown stay until their new
    /// cards arrive, so a reload never blanks the page.
    func load() async {
        loadsRunning += 1
        defer { loadsRunning -= 1 }
        loadGeneration += 1
        calendarRetry?.cancel()
        calendarRetry = nil
        calendarRetries = 0
        let generation = loadGeneration
        async let revision = APIClient.shared.homeRevision()
        let settings: HomeSettings
        do {
            settings = try await APIClient.shared.homeSettings(view: view)
        } catch {
            if shelves.isEmpty { loadError = error.localizedDescription }
            isLoading = false
            return
        }
        self.revision = await revision
        guard generation == loadGeneration else { return }
        self.settings = settings
        plan = PlannedShelf.plan(settings, profile: AppSession.shared.profile)
        HomeViewsStore.shared.update(settings.views)
        activate()
        let skipped = settings.shelves.filter { config in config.enabled == true && !plan.contains { $0.id == config.id } }
        Self.log.info("\(view) shelves: \(plan.map(\.id).joined(separator: ", "))"
            + (skipped.isEmpty ? "" : "; not supported: \(skipped.map(\.id).joined(separator: ", "))"))
        rows = rows.filter { id, _ in plan.contains { $0.id == id } }
        await loadRows(plan, generation: generation)
    }

    /// Hands this view's layout and rows to Settings › Home Layout (which shows the rows of
    /// the Home view on screen).
    func activate() {
        guard let settings else { return }
        HomeLayoutStore.shared.update(profile: settings.layout, shelves: plan.filter { $0.id != HomeShelf.promotedTopTenID }.map {
            ShelfLayoutInfo(id: $0.id, title: $0.config.title, landscapeByDefault: ShelfStyle.isLandscapeByDefault($0.config))
        })
    }

    /// Reloads only when the server's home manifest changed (on returning to Home,
    /// waking the app, and every few minutes).
    func refreshIfStale() async {
        guard !isLoading, loadsRunning == 0, checksRunning == 0, let known = revision else { return }
        checksRunning += 1
        defer { checksRunning -= 1 }
        if let current = await APIClient.shared.homeRevision(), current != known { return await load() }
        let retry = plan.filter { failed.contains($0.id) || (calendarRetry == nil && calendarPending.contains($0.id)) }
        if !retry.isEmpty { await loadRows(retry, generation: loadGeneration) }
    }

    /// Reloads the rows built from Continue Watching and playback (after playing, hiding).
    func reloadPlaybackRows() async {
        guard settings != nil else { return await load() }
        // A full load already running fetches these rows too (a title hidden posts both changes).
        guard loadsRunning == 0 else { return }
        let affected = plan.filter(\.source.followsPlayback)
        await loadRows(affected, generation: loadGeneration)
    }

    private func loadRows(_ planned: [PlannedShelf], generation: Int) async {
        guard let settings, !planned.isEmpty else {
            publish()
            isLoading = false
            return
        }
        // The watchlist row is built here from the shared store, never in a task: a
        // task would hold the list as it was when the load began and could overwrite
        // a newer one that arrived meanwhile.
        if let shelf = planned.first(where: { $0.source == .watchlist }) {
            rows[shelf.id] = shelf.watchlistRow(watchlist, settings: settings)
        }
        let planned = planned.filter { $0.source != .watchlist }
        let context = HomeContext(settings: settings, plan: planned)
        revealed = !slots.isEmpty
        revealDue = false
        // A row already showing cards reloads straight to its complete form, so a refresh
        // never trades its full metadata for the quick first pass.
        let phases = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, rows[$0.id] == nil ? ShelfPhase.cards : .complete) })
        for shelf in planned {
            completions[shelf.id]?.cancel()
            failed.remove(shelf.id)
            if rows[shelf.id] == nil { loading.insert(shelf.id) }
        }
        if revealed { publish() }
        let reveal = Task { [weak self] in
            try? await Task.sleep(for: Self.revealAfter)
            guard let self, !Task.isCancelled, generation == loadGeneration else { return }
            revealDue = true
            revealIfReady()
        }
        defer { reveal.cancel() }

        var failure: Error?
        var toComplete: [PlannedShelf] = []
        var pendingNow: [PlannedShelf] = []
        let started = ContinuousClock.now
        // Unstructured tasks rather than a task group: Swift 6.4 -O miscompiles a group
        // child returning `(id, .success(try await …))` from do/catch (swiftlang/swift#93208).
        // The group reads its first result as nil, tears down with children still running,
        // and the next one to finish aborts ("Pure virtual function called!").
        let (finished, sink) = AsyncStream.makeStream(of: (String, Result<HomeShelf?, Error>).self)
        let loads = planned.map { shelf in
            let phase = phases[shelf.id] ?? .cards
            return Task.detached {
                // Await before building the tuple, clear of the miscompiled shape.
                let result: Result<HomeShelf?, Error>
                do { result = .success(try await shelf.load(context, phase: phase)) } catch { result = .failure(error) }
                sink.yield((shelf.id, result))
            }
        }
        Task.detached {
            for load in loads { await load.value }
            sink.finish()
        }
        await withTaskCancellationHandler {
            for await (id, result) in finished {
                guard generation == loadGeneration else { continue }
                let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.seconds, .milliseconds]))
                loading.remove(id)
                switch result {
                case let .success(row?):
                    calendarPending.remove(id)
                    rows[id] = row
                    Self.log.info("\(id): \(row.cards.count) cards in \(elapsed)")
                    if phases[id] == .cards, !row.cards.isEmpty,
                       let shelf = planned.first(where: { $0.id == id }), shelf.completesLater {
                        toComplete.append(shelf)
                    }
                case .success(nil):
                    calendarPending.remove(id)
                    rows[id] = nil
                    Self.log.info("\(id): nothing to show")
                // Not a failure: the row keeps its placeholder until a retry fills it.
                case .failure(is HomeCalendarPending):
                    if rows[id] == nil { loading.insert(id) }
                    calendarPending.insert(id)
                    if let shelf = planned.first(where: { $0.id == id }) { pendingNow.append(shelf) }
                // A failed row keeps what it showed; Continue Watching's failure is the page's error.
                case let .failure(error):
                    Self.log.error("\(id): failed in \(elapsed): \(error.localizedDescription)")
                    if rows[id] == nil { failed.insert(id) }
                    if id == HomeShelf.continueWatchingID || failure == nil { failure = error }
                }
                if revealed { publish() } else { revealIfReady() }
            }
        } onCancel: {
            loads.forEach { $0.cancel() }
        }
        guard generation == loadGeneration else { return }
        if pendingNow.isEmpty {
            if planned.contains(where: \.source.usesCalendar) { calendarRetries = 0 }
        } else {
            retryPendingCalendar(pendingNow, generation: generation)
        }
        publish()
        // Complete passes wait for every row's first cards, so none queues ahead of an empty row.
        for shelf in toComplete { complete(shelf, context: context, generation: generation) }
        // Nothing to show at all: the page shows the error instead of a column of failed rows.
        loadError = shelves.isEmpty ? failure?.localizedDescription : nil
        isLoading = false
        if topShelfContinue == nil || planned.contains(where: \.source.followsPlayback) {
            await syncTopShelf(context)
        }
    }

    /// The server is still building the calendar (right after a restart): asks again every
    /// 10 s, up to 6 times, then quietly drops the rows until the next refresh.
    private func retryPendingCalendar(_ shelves: [PlannedShelf], generation: Int) {
        guard calendarRetries < 6 else {
            Self.log.info("calendar still building after \(calendarRetries) retries; giving up for now")
            calendarRetries = 0
            calendarRetry = nil
            shelves.forEach { loading.remove($0.id) }
            return
        }
        calendarRetries += 1
        Self.log.info("calendar still building; retry \(calendarRetries)/6")
        calendarRetry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled, generation == loadGeneration else { return }
            calendarRetry = nil
            await loadRows(shelves, generation: generation)
        }
    }

    /// Fetches a progressive row's complete form (full metadata, exact total) behind its
    /// first cards (and a `startsPartial` row's remaining cards). The server keeps the cards'
    /// ids, so focus stays where it is. A failure keeps the first cards.
    private func complete(_ shelf: PlannedShelf, context: HomeContext, generation: Int) {
        completions[shelf.id]?.cancel()
        completions[shelf.id] = Task { [weak self] in
            let started = ContinuousClock.now
            let row: HomeShelf?
            do { row = try await CompletionGate.run { try await shelf.load(context, phase: .complete) } } catch {
                if !(error is CancellationError) { Self.log.error("\(shelf.id): completing failed: \(error.localizedDescription)") }
                return
            }
            guard let self, !Task.isCancelled, generation == loadGeneration, let row, !row.cards.isEmpty else { return }
            Self.log.info("\(shelf.id): completed to \(row.cards.count) cards in \((ContinuousClock.now - started).formatted(.units(allowed: [.seconds, .milliseconds])))")
            rows[shelf.id] = row
            completions[shelf.id] = nil
            publish()
        }
    }

    // MARK: Top Shelf

    /// Refreshes the Top Shelf's Continue Watching (reusing this load's fetch when Home has
    /// the row, else fetching it) and rewrites the snapshot. A failed fetch keeps the last one.
    private func syncTopShelf(_ context: HomeContext) async {
        let items = context.loadsContinueWatching
            ? try? await context.allContinueWatching()
            : try? await APIClient.shared.continueWatching()
        guard let items, !Task.isCancelled else { return }
        // An episode that hasn't aired can't be resumed from the home screen.
        topShelfContinue = items.filter { !$0.isUpcoming }
        writeTopShelf()
    }

    private func writeTopShelf() {
        guard let topShelfContinue else { return }
        let shown = settings?.hideWatched == true ? watchlist.filter { $0.watchState != "complete" } : watchlist
        TopShelfSync.update(continueWatching: topShelfContinue, watchlist: shown)
    }

    /// Reveals a first load once `revealAfter` has passed and the top row is ready.
    private func revealIfReady() {
        guard !revealed, revealDue, topRowReady else { return }
        revealed = true
        publish()
        isLoading = false
    }

    /// The first row with cards is in, and no row above it is still loading: rows above
    /// it came back empty or failed. Until then the page keeps its spinner rather than
    /// opening on a placeholder that the row would replace.
    private var topRowReady: Bool {
        for shelf in visiblePlan {
            if let row = rows[shelf.id], !row.cards.isEmpty { return true }
            if loading.contains(shelf.id) { return false }
        }
        return false
    }

    /// The planned rows minus those hidden in Settings › Home Layout.
    private var visiblePlan: [PlannedShelf] {
        let layout = HomeLayoutStore.shared
        return plan.filter { !layout.isHidden($0.id) }
    }

    private func publish() {
        let visible = visiblePlan
        let next = visible.compactMap { shown($0.id) }.filter { !$0.cards.isEmpty }
        if next != shelves { shelves = next }
        let nextSlots = visible.compactMap { shelf -> HomeSlot? in
            if let row = shown(shelf.id) { return row.cards.isEmpty ? nil : .shelf(row) }
            if loading.contains(shelf.id) { return .loading(id: shelf.id, title: shelf.config.title) }
            if failed.contains(shelf.id) { return .failed(id: shelf.id, title: shelf.config.title) }
            return nil
        }
        if nextSlots != slots { slots = nextSlots }
    }

    /// A row as Home shows it: Watch Something drops its Search card while the Search
    /// tab is hidden (the card only switches to that tab).
    private func shown(_ id: String) -> HomeShelf? {
        guard let row = rows[id] else { return nil }
        let search = HomeShelf.watchSomethingSearchID
        guard !MenuTabsStore.shared.isVisible(.search), row.cards.contains(where: { $0.id == search }) else { return row }
        return row.removing(card: search)
    }

    private func rebuildWatchlist() {
        guard let settings, let shelf = plan.first(where: { $0.source == .watchlist }) else { return }
        rows[shelf.id] = shelf.watchlistRow(watchlist, settings: settings)
        publish()
    }

    // MARK: Changes made on Home

    /// Drops a card from a row at once (hiding from Continue Watching).
    func remove(card id: String, from shelf: String) {
        guard let row = rows[shelf] else { return }
        rows[shelf] = row.removing(card: id)
        publish()
    }
}

/// Complete passes in flight across every Home view: each can take a while on a cold
/// server and holds a connection, so only a few run at once.
@MainActor
private enum CompletionGate {
    private static let limit = 4
    private static var running = 0
    private static var waiting: [CheckedContinuation<Void, Never>] = []

    static func run<T>(_ work: () async throws -> T) async rethrows -> T {
        if running < limit { running += 1 } else { await withCheckedContinuation { waiting.append($0) } }
        // A finished pass hands its slot straight to the next waiting one.
        defer { if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() } }
        return try await work()
    }
}
