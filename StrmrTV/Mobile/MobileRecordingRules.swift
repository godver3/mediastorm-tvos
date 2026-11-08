#if os(iOS)
import SwiftUI

/// Rules & Buffers (the management cards above Expo's phone recordings list): the profile's
/// default padding around new recordings, a new regex rule, and the recurring recordings,
/// each paused / resumed with a toggle, its padding edited on its own page, and deleted with
/// a swipe (confirmed; the server cancels what it had scheduled).
struct MobileRecordingRulesView: View {
    @StateObject private var store = MobileRecordingRulesStore()
    @State private var pattern = ""
    @State private var deleting: RecordingRule?

    var body: some View {
        Form {
            Section {
                if let settings = store.settings {
                    MinutesStepper(title: "Before", seconds: settings.paddingBeforeSeconds) { value in
                        store.saveSettings(RecordingSettings(paddingBeforeSeconds: value,
                                                             paddingAfterSeconds: settings.paddingAfterSeconds))
                    }
                    MinutesStepper(title: "After", seconds: settings.paddingAfterSeconds) { value in
                        store.saveSettings(RecordingSettings(paddingBeforeSeconds: settings.paddingBeforeSeconds,
                                                             paddingAfterSeconds: value))
                    }
                } else if store.loading {
                    ProgressView()
                }
            } header: {
                Text("Default Buffers")
            } footer: {
                Text("Added before and after new guide and manual recordings.")
            }

            Section {
                TextField("For example: (News|Weather).*", text: $pattern)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("rules.pattern")
                Button("Create Regex Rule") {
                    let text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { if await store.createRegex(text) { pattern = "" } }
                }
                .disabled(pattern.trimmingCharacters(in: .whitespaces).isEmpty || store.busy)
            } header: {
                Text("Add a Regex Rule")
            } footer: {
                Text("Matches guide titles in the next 7 days on every channel, ignoring case. Use (?-i) to match exact capitalization.")
            }

            Section {
                if store.rules.isEmpty, !store.loading {
                    Text("No rules yet. Long-press a programme on Live TV and choose Record Series to record it whenever it airs.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.rules) { rule in
                    NavigationLink {
                        MobileRecordingRuleEditor(rule: rule, store: store)
                    } label: {
                        MobileRecordingRuleRow(rule: rule, store: store)
                    }
                    .swipeActions {
                        Button(role: .destructive) { deleting = rule } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            } header: {
                Text("Recurring Recordings")
            }

            if let error = store.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Rules & Buffers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.load() }
        .task { await store.load() }
        .confirmationDialog("Delete recurring recording?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible,
                            presenting: deleting) { rule in
            Button("Delete Rule", role: .destructive) { Task { await store.delete(rule) } }
            Button("Keep Rule", role: .cancel) {}
        } message: { rule in
            Text("Remove the rule for “\(rule.pattern)”? Upcoming recordings from this rule will be cancelled.")
        }
    }
}

private struct MobileRecordingRuleRow: View {
    let rule: RecordingRule
    @ObservedObject var store: MobileRecordingRulesStore

    var body: some View {
        Toggle(isOn: Binding(get: { rule.enabled }, set: { on in Task { await store.update(rule, enabled: on) } })) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.pattern).font(.headline).lineLimit(2)
                    Text(rule.isRegex ? "REGEX" : "TITLE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(MobileRecordingRulesStore.summary(rule)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(store.busy)
    }
}

/// One rule's padding and pause, saved as they change.
private struct MobileRecordingRuleEditor: View {
    let rule: RecordingRule
    @ObservedObject var store: MobileRecordingRulesStore

    private var current: RecordingRule { store.rules.first { $0.id == rule.id } ?? rule }

    var body: some View {
        let rule = current
        Form {
            Section {
                LabeledContent("Matches", value: rule.pattern)
                LabeledContent("Type", value: rule.isRegex ? String(localized: "Regex") : String(localized: "Title"))
                LabeledContent("Channels", value: rule.allChannels ? String(localized: "All channels")
                               : rule.channelName ?? String(localized: "Selected channel"))
                if rule.newOnly { LabeledContent("Airings", value: String(localized: "New episodes only")) }
                Toggle("Enabled", isOn: Binding(get: { rule.enabled },
                                                set: { on in Task { await store.update(rule, enabled: on) } }))
            }
            Section("Buffers") {
                MinutesStepper(title: "Before", seconds: rule.paddingBeforeSeconds) { value in
                    Task { await store.update(rule, paddingBefore: value) }
                }
                MinutesStepper(title: "After", seconds: rule.paddingAfterSeconds) { value in
                    Task { await store.update(rule, paddingAfter: value) }
                }
            }
            if let error = store.error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(rule.pattern)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Whole minutes from 0 to 60, as the server takes them; reports seconds.
private struct MinutesStepper: View {
    let title: LocalizedStringKey
    let seconds: Int
    let onChange: (Int) -> Void

    var body: some View {
        let minutes = seconds / 60
        Stepper(value: Binding(get: { minutes }, set: { onChange($0 * 60) }), in: 0...60) {
            LabeledContent(title, value: String(localized: "\(minutes) min"))
        }
    }
}

@MainActor
final class MobileRecordingRulesStore: ObservableObject {
    @Published private(set) var rules: [RecordingRule] = []
    @Published private(set) var settings: RecordingSettings?
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var settingsSave: Task<Void, Never>?
    private let api = APIClient.shared

    func load() async {
        loading = true
        defer { loading = false }
        async let rules = api.recordingRules()
        async let settings = try? api.recordingSettings()
        do {
            self.rules = try await rules
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
        if let loaded = await settings { self.settings = loaded }
    }

    /// Shown at once; saved after the stepper settles.
    func saveSettings(_ new: RecordingSettings) {
        let previous = settings
        settings = new
        settingsSave?.cancel()
        settingsSave = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            do {
                try await api.saveRecordingSettings(new)
                error = nil
            } catch {
                settings = previous
                self.error = error.localizedDescription
            }
        }
    }

    func createRegex(_ pattern: String) async -> Bool {
        guard !pattern.isEmpty else { return false }
        return await run { try await self.api.createRegexRecordingRule(pattern) }
    }

    func update(_ rule: RecordingRule, enabled: Bool? = nil, paddingBefore: Int? = nil, paddingAfter: Int? = nil) async {
        _ = await run {
            try await self.api.updateRecordingRule(rule.id, enabled: enabled, paddingBefore: paddingBefore,
                                                   paddingAfter: paddingAfter)
        }
    }

    func delete(_ rule: RecordingRule) async {
        _ = await run { try await self.api.deleteRecordingRule(rule.id) }
    }

    private func run(_ action: () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await action()
            error = nil
            rules = (try? await api.recordingRules()) ?? rules
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    static func summary(_ rule: RecordingRule) -> String {
        var parts = [rule.allChannels ? String(localized: "All channels") : rule.channelName ?? String(localized: "Selected channel")]
        if rule.newOnly { parts.append(String(localized: "New only")) }
        parts.append(rule.enabled ? String(localized: "Enabled") : String(localized: "Paused"))
        return parts.joined(separator: " · ")
    }
}
#endif
