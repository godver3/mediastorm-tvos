#if os(iOS)
import SwiftUI

/// Settings › Server on the phone: the address and its reachability, the speed test (which
/// also saves the adaptive-playback estimate), Connection, the admin web UI and Change Server.
/// Expo's phone Server section, less the address field (changing server signs out here, as on
/// the TV).
struct MobileServerSection: View {
    @ObservedObject private var session = AppSession.shared
    @ObservedObject private var adaptive = AdaptiveThroughput.shared
    @State private var status: Status = .checking
    @State private var confirmChangeServer = false

    enum Status: Equatable { case checking, connected, unreachable(String) }

    var body: some View {
        Section {
            // A Section's modifiers apply to each row, so the section's own go on one row.
            LabeledContent("Address", value: address)
                .task { await check() }
                .onAppear { adaptive.reload() }
            LabeledContent("Status") {
                switch status {
                case .checking:
                    Text("Checking…")
                case .connected:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Connected")
                    }
                    .foregroundStyle(.green)
                case let .unreachable(message):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(message).lineLimit(3)
                    }
                    .foregroundStyle(.orange)
                }
            }
            Button("Check Connection") { Task { await check() } }
                .disabled(status == .checking)
            Button {
                Task { await adaptive.runManual() }
            } label: {
                LabeledContent("Test Connection Speed") {
                    Text(adaptive.manualRunning ? String(localized: "Testing…") : speedText)
                }
            }
            .disabled(adaptive.manualRunning)
            LabeledContent("Adaptive Speed", value: estimateText)
            NavigationLink {
                MobileConnectionSettingsView()
            } label: {
                Label("Connection", systemImage: "network")
            }
            if !session.isRemote, let admin = adminURL {
                Link(destination: admin) {
                    Label("Server Web UI", systemImage: "safari")
                }
            }
            Button("Change Server…") { confirmChangeServer = true }
                .confirmationDialog("Change server?", isPresented: $confirmChangeServer, titleVisibility: .visible) {
                    Button("Change Server", role: .destructive) { session.changeServer() }
                } message: {
                    Text("You'll sign in again on the new server.")
                }
        } header: {
            Text("Server")
        } footer: {
            Text("Test Connection Speed downloads test data from the server; with adaptive playback on, searches use the result to pick a release that fits. Server settings are managed in the server's web UI.")
        }
    }

    private var address: String {
        session.isRemote ? String(localized: "Remote access (iroh)") : session.serverURL.map(ServerAddress.display) ?? "—"
    }

    private var adminURL: URL? { session.serverURL?.appending(path: "admin") }

    private var speedText: String {
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
        return AdaptiveThroughputStore.isFresh(estimate)
            ? "\(Self.mbps(estimate.measuredMbps)) · \(source), \(when)"
            : String(localized: "Expired (\(Self.mbps(estimate.measuredMbps)), \(when))")
    }

    private static func mbps(_ value: Double) -> String {
        String(localized: "\(value.formatted(.number.precision(.fractionLength(1)))) Mbps")
    }

    private func check() async {
        guard let url = session.serverURL else { return }
        status = .checking
        do {
            try await APIClient.shared.checkHealth(of: url)
            status = .connected
        } catch {
            status = .unreachable(error.localizedDescription)
        }
    }
}

/// Settings › About on the phone: app and server versions, the device ID (copyable), the
/// airing-schedule credit, and the log upload / share for bug reports.
struct MobileAboutSection: View {
    @ObservedObject private var session = AppSession.shared
    @ObservedObject private var logs = LogUploader.shared
    @State private var logFile: URL?

    var body: some View {
        Section("About") {
            // On one row: a Section's modifiers apply to each of its rows.
            LabeledContent("Version", value: "\(Config.appVersion) (\(Config.buildNumber))")
                .task { logFile = await Self.exportLog() }
            LabeledContent("Server Version", value: serverVersion)
            LabeledContent("Device ID") {
                Text(Config.clientID).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            .contextMenu {
                Button("Copy Device ID", systemImage: "doc.on.doc") { UIPasteboard.general.string = Config.clientID }
            }
            Button {
                Task { await logs.uploadNow() }
            } label: {
                LabeledContent("Upload Logs") {
                    Text(logStatus)
                }
            }
            .disabled(logs.status == .uploading)
            if let logFile {
                ShareLink(item: logFile) {
                    Label("Share Logs", systemImage: "square.and.arrow.up")
                }
            }
            if let tvmaze = URL(string: "https://www.tvmaze.com/api") {
                Link(destination: tvmaze) {
                    Text("Airing schedules: TVmaze (CC BY-SA)").font(.footnote)
                }
            }
        }
    }

    private var serverVersion: String {
        guard let v = session.serverVersion else { return "—" }
        if let build = v.buildId, !build.isEmpty { return "\(v.version) (\(build))" }
        return v.version
    }

    private var logStatus: String {
        switch logs.status {
        case .idle: ""
        case .uploading: String(localized: "Uploading…")
        case let .uploaded(date): String(localized: "Sent \(date.formatted(date: .omitted, time: .shortened))")
        case let .failed(message): message
        }
    }

    /// The newest megabyte of the app log, copied to a temporary file the share sheet can send.
    private static func exportLog() async -> URL? {
        let (text, _) = await LogFile.shared.tail(maxBytes: 1 << 20)
        guard !text.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MediaStorm-log.txt")
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
#endif
