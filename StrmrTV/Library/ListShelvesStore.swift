import Foundation

/// The profile's Home shelf config as the Lists tab reads it (streaming services, connected
/// lists, collection hubs). One per profile, loaded with the tabs so the Lists tab draws
/// its rows on first open instead of swapping them in after.
@MainActor
final class ListShelvesStore: ObservableObject {
    /// nil until the first load.
    @Published private(set) var shelves: [ShelfConfig]?

    private var refreshTask: Task<Void, Never>?

    /// Loads the config; concurrent callers share one request, and a failure keeps what was shown.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task {
            if let loaded = try? await APIClient.shared.shelfConfigs() { shelves = loaded }
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }
}
