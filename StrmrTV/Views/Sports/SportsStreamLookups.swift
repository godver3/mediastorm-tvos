import Foundation

/// The stream picker's Stremio lookups (`GET /api/live/stremio/streams` per channel), at most
/// four at a time (`SportsStreamOptions.concurrency` workers), each given 25 s (a timeout counts as
/// a failure); `states` updates as each one finishes. Cancelling
/// the task that runs `run` (the picker going away, a new search) stops the rest.
@MainActor
final class SportsStreamLookups: ObservableObject {
    @Published private(set) var states: [String: SportsStreamLookup] = [:]

    private var queue: [LiveChannel] = []
    private let fetch: @MainActor (LiveChannel) async throws -> [LiveStremioStream]

    init(fetch: @escaping @MainActor (LiveChannel) async throws -> [LiveStremioStream] = {
        try await APIClient.shared.liveStremioStreams($0, timeout: SportsStreamOptions.lookupTimeout)
    }) {
        self.fetch = fetch
    }

    /// Looks up each Stremio channel among `matches` that hasn't answered yet (one a cancelled
    /// run left pending is asked again).
    func run(_ matches: [SportsStreamMatch]) async {
        let urls = Set(SportsStreamOptions.lookupURLs(matches).filter { states[$0] == nil || states[$0] == .pending })
        var seen = Set<String>()
        let channels = matches.filter { urls.contains($0.channelUrl) && seen.insert($0.channelUrl).inserted }.map(\.channel)
        guard !channels.isEmpty else { return }
        for channel in channels { states[channel.url] = .pending }
        queue = channels
        // Side by side, without a task group (Swift 6.4 -O miscompiles them, see HomeStore).
        async let a: Void = worker()
        async let b: Void = worker()
        async let c: Void = worker()
        async let d: Void = worker()
        _ = await (a, b, c, d)
    }

    private func worker() async {
        while !Task.isCancelled, !queue.isEmpty {
            let channel = queue.removeFirst()
            do {
                let streams = try await fetch(channel)
                guard !Task.isCancelled else { return }
                states[channel.url] = .loaded(streams)
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                states[channel.url] = .failed
            }
        }
    }
}
