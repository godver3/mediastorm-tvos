import Foundation

/// One piece of deferred work that a newer request replaces, held by reference so a view
/// can restart it (on every focus move, say) without the state change re-rendering it.
@MainActor
final class PendingTask {
    private var task: Task<Void, Never>?

    func restart(_ work: @escaping @MainActor () async -> Void) {
        task?.cancel()
        task = Task { await work() }
    }
}
