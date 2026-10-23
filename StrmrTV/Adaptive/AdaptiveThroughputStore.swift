import Foundation

/// How a throughput estimate was measured: Settings' speed test, or the automatic idle probe.
enum AdaptiveThroughputSource: String, Codable, Sendable {
    case manual, idle
}

/// One route's measured client ↔ server throughput (the Expo app's `AdaptiveThroughputContext`).
/// `measuredAt` is Unix seconds, as the `X-Adaptive-Throughput-Measured-At` header carries it.
struct AdaptiveThroughputEstimate: Codable, Equatable, Sendable {
    let measuredMbps: Double
    let measuredAt: Int
    let source: AdaptiveThroughputSource

    var measuredDate: Date { Date(timeIntervalSince1970: TimeInterval(measuredAt)) }

    /// The headers searches and prequeues carry (`api.ts` `searchIndexer` / `prequeuePlayback`).
    var headers: [String: String] {
        [AdaptiveThroughputStore.mbpsHeader: Self.headerValue(measuredMbps),
         AdaptiveThroughputStore.measuredAtHeader: String(measuredAt)]
    }

    /// JS `String(number)`: "84.2", "120" (no trailing ".0").
    static func headerValue(_ mbps: Double) -> String {
        mbps == mbps.rounded() ? String(Int(mbps)) : String(mbps)
    }
}

/// Throughput estimates per server route, a port of the Expo app's `services/adaptive-throughput.ts`:
/// one estimate per route key (the server origin, or `transport:iroh` over remote access), kept in
/// `UserDefaults` under the Expo storage key's shape (`{version: 2, routes: {…}}`). An estimate is
/// sent only while fresh: positive, finite and measured in the last two hours (the backend
/// independently rejects anything older than a day).
struct AdaptiveThroughputStore {
    static let storageKey = "strmr.adaptive.throughput.v2"
    static let mbpsHeader = "X-Adaptive-Throughput-Mbps"
    static let measuredAtHeader = "X-Adaptive-Throughput-Measured-At"
    /// Expo `ESTIMATE_TTL_MS`: often enough to follow Wi-Fi / route changes without a
    /// benchmark on every foreground.
    static let ttl: TimeInterval = 2 * 60 * 60

    private struct Stored: Codable {
        var version = 2
        var routes: [String: AdaptiveThroughputEstimate] = [:]
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Expo `routeKey`: trimmed, trailing slashes dropped.
    static func routeKey(_ base: String) -> String {
        var key = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while key.hasSuffix("/") { key.removeLast() }
        return key
    }

    /// Expo's validity rule: a positive finite speed measured no more than `ttl` ago (and not
    /// in the future).
    static func isFresh(_ estimate: AdaptiveThroughputEstimate, now: Date = .now) -> Bool {
        guard estimate.measuredMbps.isFinite, estimate.measuredMbps > 0 else { return false }
        let age = now.timeIntervalSince1970 - TimeInterval(estimate.measuredAt)
        return age >= 0 && age <= ttl
    }

    /// The stored estimate for `route`, fresh or not (Settings shows it either way).
    func stored(for route: String) -> AdaptiveThroughputEstimate? {
        read().routes[Self.routeKey(route)]
    }

    /// The estimate to send for `route`: only a fresh one (Expo `getAdaptiveThroughputContext`).
    func fresh(for route: String, now: Date = .now) -> AdaptiveThroughputEstimate? {
        stored(for: route).flatMap { Self.isFresh($0, now: now) ? $0 : nil }
    }

    /// Saves a measurement (rounded to 0.1 Mbps, as Expo saves it). Nil for a non-positive or
    /// non-finite speed, which Expo refuses with an error.
    @discardableResult
    func save(route: String, mbps: Double, source: AdaptiveThroughputSource,
              measuredAt: Date = .now) -> AdaptiveThroughputEstimate? {
        guard mbps.isFinite, mbps > 0 else { return nil }
        let estimate = AdaptiveThroughputEstimate(measuredMbps: (mbps * 10).rounded() / 10,
                                                  measuredAt: Int(measuredAt.timeIntervalSince1970),
                                                  source: source)
        var store = read()
        store.routes[Self.routeKey(route)] = estimate
        if let data = try? JSONEncoder().encode(store) { defaults.set(data, forKey: Self.storageKey) }
        return estimate
    }

    private func read() -> Stored {
        guard let data = defaults.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data), stored.version == 2 else { return Stored() }
        return stored
    }
}
