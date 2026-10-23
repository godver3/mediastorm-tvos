import Foundation

private let speedLog = AppLog(category: "adaptive")

/// One `/api/debug/speed-test` download, timed like the Expo app's `testBackendConnectionSpeed`:
/// `setupMs` until the response starts, `transferMs` from there to the last byte.
struct SpeedTestFlow: Equatable, Sendable {
    let receivedBytes: Int
    let elapsedMs: Double
    let setupMs: Double
    let transferMs: Double
}

/// One aggregate sample over parallel flows (Expo `testBackendConnectionSpeedAggregate`).
struct SpeedTestSample: Equatable, Sendable {
    let receivedBytes: Int
    let elapsedMs: Double
    let setupMs: Double
    let transferMs: Double
    let speedMbps: Double
    let parallelStreams: Int
}

/// The speed test's plans and maths, kept pure for the unit tests.
enum ConnectionSpeedTest {
    /// A sample-size ladder: each size is tried in turn until one takes `minElapsedMs`.
    struct Plan: Equatable, Sendable {
        let samples: [Int]
        let parallelStreams: Int
        let minElapsedMs: Double
    }

    private static let mib = 1024 * 1024
    /// Expo `utils/adaptivePlayback.ts`: the automatic idle probe, half the manual test's worst case.
    static let idle = Plan(samples: [4 * mib, 16 * mib, 64 * mib], parallelStreams: 4, minElapsedMs: 750)
    /// Expo `app/(drawer)/settings.tsx` `CONNECTION_SPEED_TEST_*`: Settings' Test Connection Speed.
    static let manual = Plan(samples: [8 * mib, 32 * mib, 128 * mib], parallelStreams: 4, minElapsedMs: 1500)

    /// Splits `total` bytes over 1…8 flows, the remainder one byte each on the first flows.
    static func flowBytes(total: Int, streams: Int) -> [Int] {
        let total = max(1, total)
        let streams = max(1, min(8, streams))
        let base = total / streams, remainder = total % streams
        return (0..<streams).map { base + ($0 < remainder ? 1 : 0) }
    }

    /// Megabits per second over `transferMs`.
    static func mbps(bytes: Int, transferMs: Double) -> Double {
        Double(bytes) * 8 / (max(transferMs, 1) / 1000) / 1_000_000
    }

    /// Combines parallel flows as Expo does: the wall time of the whole sample, less the
    /// quickest flow's setup, is the transfer time.
    static func aggregate(_ flows: [SpeedTestFlow], elapsedMs: Double) -> SpeedTestSample {
        let elapsed = max(elapsedMs, 1)
        let setup = flows.map(\.setupMs).min() ?? 0
        let transfer = max(elapsed - setup, 1)
        let bytes = flows.reduce(0) { $0 + $1.receivedBytes }
        return SpeedTestSample(receivedBytes: bytes, elapsedMs: elapsed, setupMs: setup, transferMs: transfer,
                               speedMbps: mbps(bytes: bytes, transferMs: transfer), parallelStreams: flows.count)
    }

    /// The ladder stops once a sample took long enough to be trusted.
    static func isLongEnough(_ sample: SpeedTestSample, plan: Plan) -> Bool {
        sample.transferMs >= plan.minElapsedMs
    }
}

enum SpeedTestError: LocalizedError {
    case status(Int)
    case shortRead(received: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case let .status(code): String(localized: "Speed test failed (HTTP \(code))")
        case let .shortRead(received, expected): String(localized: "Speed test received \(received) of \(expected) bytes")
        }
    }
}

extension APIClient {
    /// Runs `plan`'s ladder against the server and returns the last sample taken.
    func runSpeedTest(_ plan: ConnectionSpeedTest.Plan) async throws -> SpeedTestSample {
        var last: SpeedTestSample?
        for bytes in plan.samples {
            let sample = try await speedTestSample(totalBytes: bytes, streams: plan.parallelStreams)
            last = sample
            speedLog.info("speed test sample requestedBytes=\(bytes) mbps=\(String(format: "%.1f", sample.speedMbps)) "
                          + "elapsedMs=\(Int(sample.elapsedMs)) setupMs=\(Int(sample.setupMs)) transferMs=\(Int(sample.transferMs))")
            if ConnectionSpeedTest.isLongEnough(sample, plan: plan) { break }
        }
        return last!
    }

    /// One aggregate sample: `totalBytes` over parallel `/api/debug/speed-test` downloads.
    func speedTestSample(totalBytes: Int, streams: Int) async throws -> SpeedTestSample {
        let split = ConnectionSpeedTest.flowBytes(total: totalBytes, streams: streams)
        let sampleID = Int(Date().timeIntervalSince1970 * 1000)
        let requests = split.enumerated().map { index, bytes in
            speedTestRequest(bytes: bytes, sampleID: sampleID, flow: index + 1, streams: split.count)
        }
        let started = ContinuousClock.now
        let flows = try await withThrowingTaskGroup(of: SpeedTestFlow.self) { group in
            for (request, bytes) in zip(requests, split) {
                group.addTask { try await Self.speedTestFlow(request, expected: bytes) }
            }
            var flows: [SpeedTestFlow] = []
            for try await flow in group { flows.append(flow) }
            return flows
        }
        let elapsed = (ContinuousClock.now - started) / .milliseconds(1)
        return ConnectionSpeedTest.aggregate(flows, elapsedMs: elapsed)
    }

    private func speedTestRequest(bytes: Int, sampleID: Int, flow: Int, streams: Int) -> URLRequest {
        let query = ["bytes": String(bytes), "_": String(sampleID), "sampleId": String(sampleID),
                     "flow": String(flow), "streams": String(streams)]
        var req = URLRequest(url: url("/api/debug/speed-test", query: query))
        req.timeoutInterval = 120
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        for (name, value) in mediaHeaders { req.setValue(value, forHTTPHeaderField: name) }
        return req
    }

    /// Downloads one flow, timed from the task's own metrics (request start, first and last byte).
    private nonisolated static func speedTestFlow(_ request: URLRequest, expected: Int) async throws -> SpeedTestFlow {
        let metrics = MetricsCollector()
        let started = Date()
        let (data, response) = try await speedTestSession.data(for: request, delegate: metrics)
        let ended = Date()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SpeedTestError.status(status) }
        guard data.count == expected else { throw SpeedTestError.shortRead(received: data.count, expected: expected) }
        let transaction = metrics.transaction
        let responseStart = transaction?.responseStartDate ?? started
        let responseEnd = transaction?.responseEndDate ?? ended
        let ms = { (a: Date, b: Date) in max(b.timeIntervalSince(a) * 1000, 0) }
        return SpeedTestFlow(receivedBytes: data.count, elapsedMs: max(ms(started, ended), 1),
                             setupMs: ms(started, responseStart), transferMs: max(ms(responseStart, responseEnd), 1))
    }

    /// No cache, so every sample crosses the network.
    private nonisolated static let speedTestSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()
}

/// Captures a task's last transaction metrics.
private final class MetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var last: URLSessionTaskTransactionMetrics?

    var transaction: URLSessionTaskTransactionMetrics? { lock.withLock { last } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { last = metrics.transactionMetrics.last }
    }
}
