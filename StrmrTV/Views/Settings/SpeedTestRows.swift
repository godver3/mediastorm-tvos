import SwiftUI

/// Settings › Server: Test Connection Speed (the Expo Settings speed test, which also saves a
/// `manual` adaptive estimate while adaptive playback is on) and, read-only, the estimate
/// searches and prequeues currently carry for this route.
struct SpeedTestRows: View {
    @ObservedObject private var adaptive = AdaptiveThroughput.shared

    var body: some View {
        Button {
            Task { await adaptive.runManual() }
        } label: {
            LabeledContent("Test Connection Speed") { Text(resultText) }
        }
        .disabled(adaptive.manualRunning)
        .accessibilityHint(Text("Downloads test data from the server and shows the speed"))

        Button {} label: {
            LabeledContent("Adaptive Speed") { Text(estimateText).lineLimit(2) }
        }
        .accessibilityHint(Text("The speed sent with searches so adaptive playback can pick a release that fits"))
        .onAppear { adaptive.reload() }
    }

    private var resultText: String {
        if adaptive.manualRunning { return String(localized: "Testing…") }
        if let error = adaptive.manualError { return error }
        guard let result = adaptive.manualResult else { return "" }
        return "\(Self.mbps(result.sample.speedMbps)) · \(result.at.formatted(date: .omitted, time: .shortened))"
    }

    private var estimateText: String {
        guard let estimate = adaptive.estimate else { return String(localized: "Not measured") }
        let source = estimate.source == .manual ? String(localized: "speed test") : String(localized: "automatic")
        let date = estimate.measuredDate
        let when = Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened)
        let fresh = AdaptiveThroughputStore.isFresh(estimate)
        return fresh
            ? "\(Self.mbps(estimate.measuredMbps)) · \(source), \(when)"
            : String(localized: "Expired (\(Self.mbps(estimate.measuredMbps)), \(when))")
    }

    private static func mbps(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) Mbps")
    }
}
