import Foundation

/// What a tile plays: one server HLS session's playlist. Compared by identity, so a tile can
/// tell its current source from one it played before (`MultiscreenSession.fail`).
struct MultiscreenSource: Equatable {
    let id = UUID()
    let url: URL
    let sessionID: String?
}

/// One screen. Its index in `MultiscreenSession.slots` never changes; only its rectangle does.
struct MultiscreenSlot: Equatable {
    var channel: LiveChannel?
    var source: MultiscreenSource?
    /// The server session this slot owns, kept even when the start failed so it can be stopped.
    var sessionID: String?
    var loading = false
    var error: String?

    /// Shown on screen: it has a channel, or one is being tuned.
    var isOccupied: Bool { channel != nil || loading }
    var isPlaying: Bool { source != nil && error == nil && !loading }
}

/// Opens and closes the server sessions behind the screens.
@MainActor
protocol MultiscreenTransport {
    /// Opens `channel`. A nil `url` with a session ID means the server answered without a
    /// playable stream; the session is still the caller's to stop.
    func start(_ channel: LiveChannel) async throws -> (sessionID: String?, url: URL?)
    func stop(_ sessionID: String) async throws
}

enum MultiscreenError: Error {
    case noStream
    case releaseFailed
}

/// The screens and their sessions (the Expo app's `TVMultiscreenSession`). Slot identities are
/// stable; starts and stops run one at a time through a queue, so the transport can recheck the
/// provider's capacity before each start. Every tune bumps its slot's version, and a tune
/// that finds a newer version (or a closed session) when it resumes gives way.
@MainActor
final class MultiscreenSession: ObservableObject {
    static let maxScreens = 4
    static let tuneError = String(localized: "Unable to tune. Retry or choose another channel.")
    static let streamError = String(localized: "Stream unavailable. Retry or choose another channel.")
    static let releaseError = String(localized: "Unable to release stream. Try again.")

    @Published private(set) var slots = [MultiscreenSlot(), MultiscreenSlot()]
    /// The screen whose audio plays.
    @Published private(set) var audioIndex = 0
    @Published private(set) var focusedIndex = 0
    private(set) var closed = false

    private let transport: MultiscreenTransport
    private var versions = [0, 0]
    /// The channel each slot is being tuned to, so a second pick of it finds that slot.
    private var requested: [Int: LiveChannel] = [:]
    private var queue: Task<Void, Error>?

    init(transport: MultiscreenTransport) {
        self.transport = transport
    }

    var occupied: [Int] { slots.indices.filter { slots[$0].isOccupied } }

    /// The slot showing (or tuning) `channel`, by id and source.
    func index(of channel: LiveChannel) -> Int? {
        slots.indices.first { index in
            let candidate = requested[index] ?? slots[index].channel
            return candidate?.id == channel.id && candidate?.sourceId == channel.sourceId
        }
    }

    func focus(_ index: Int) {
        guard slots.indices.contains(index) else { return }
        focusedIndex = index
    }

    func listen(_ index: Int) {
        guard slots.indices.contains(index), slots[index].source != nil else { return }
        audioIndex = index
    }

    /// Puts a session that is already open (the full-screen player's) on screen 1. It is
    /// owned from here on: releasing the slot stops it.
    func adopt(_ channel: LiveChannel, url: URL, sessionID: String) {
        guard !closed, slots[0].channel == nil, !slots[0].loading else { return }
        slots[0] = MultiscreenSlot(channel: channel, source: MultiscreenSource(url: url, sessionID: sessionID),
                                   sessionID: sessionID)
    }

    /// Tunes slot `index` to `channel`; `index == slots.count` adds a slot, up to `maxScreens`.
    /// A channel already on another screen just focuses that screen. The slot shows it is
    /// tuning at once; the returned task finishes when the tune has.
    @discardableResult
    func tune(_ index: Int, to channel: LiveChannel) -> Task<Void, Never> {
        guard !closed, index >= 0, index <= slots.count else { return Task {} }
        if let duplicate = self.index(of: channel), duplicate != index {
            focus(duplicate)
            return Task {}
        }
        if index == slots.count {
            guard slots.count < Self.maxScreens else { return Task {} }
            slots.append(MultiscreenSlot())
            versions.append(0)
        }
        versions[index] += 1
        let version = versions[index]
        requested[index] = channel
        slots[index].loading = true
        slots[index].error = nil
        return enqueue { [self] in
            guard isCurrent(index, version) else { return }
            do {
                try await release(index)
                guard isCurrent(index, version) else { return }
                slots[index] = MultiscreenSlot(channel: channel, loading: true)
                let started = try await transport.start(channel)
                // Owned before it is checked, so a failed stop can be retried on exit.
                slots[index] = MultiscreenSlot(channel: channel, sessionID: started.sessionID, loading: true)
                guard let url = started.url else {
                    try await release(index)
                    throw MultiscreenError.noStream
                }
                guard isCurrent(index, version) else {
                    try await release(index)
                    return
                }
                slots[index] = MultiscreenSlot(channel: channel, source: MultiscreenSource(url: url, sessionID: started.sessionID),
                                               sessionID: started.sessionID)
            } catch {
                var slot = slots[index]
                slot.channel = slot.channel ?? channel
                slot.loading = false
                slot.error = Self.tuneError
                slots[index] = slot
            }
            if versions[index] == version { requested[index] = nil }
        }
    }

    /// The player gave up on `source`; ignored once the slot has moved on from it.
    func fail(_ index: Int, source: MultiscreenSource) {
        guard slots.indices.contains(index), slots[index].source == source else { return }
        slots[index].error = Self.streamError
    }

    /// Stops the slot's session and empties it. Its audio moves to the first slot still playing.
    @discardableResult
    func remove(_ index: Int) -> Task<Void, Never> {
        guard !closed, slots.indices.contains(index) else { return Task {} }
        versions[index] += 1
        return enqueue { [self] in
            do {
                try await release(index)
                requested[index] = nil
                if audioIndex == index { audioIndex = slots.firstIndex { $0.source != nil } ?? 0 }
            } catch {
                slots[index].error = Self.releaseError
            }
        }
    }

    /// Stops every session. Throws when any stop failed; calling it again retries those.
    func close() async throws {
        closed = true
        versions = versions.map { $0 + 1 }
        try await enqueueThrowing { [self] in
            // All at once; each failed stop keeps its slot (and session ID) for the retry.
            let releases = slots.indices.map { index in Task { (try? await release(index)) != nil } }
            var failed = false
            for release in releases where !(await release.value) { failed = true }
            if failed { throw MultiscreenError.releaseFailed }
        }
    }

    // MARK: Plumbing

    private func isCurrent(_ index: Int, _ version: Int) -> Bool {
        !closed && versions[index] == version
    }

    private func release(_ index: Int) async throws {
        if let id = slots[index].sessionID { try await transport.stop(id) }
        slots[index] = MultiscreenSlot()
    }

    /// Runs `operation` after everything queued before it, whether that succeeded or not.
    private func enqueueThrowing(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        try await schedule(operation).value
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let task = schedule(operation)
        return Task { _ = await task.result }
    }

    private func schedule(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, Error> {
        let previous = queue
        let task = Task { @MainActor in
            _ = await previous?.result
            try await operation()
        }
        queue = task
        return task
    }
}
