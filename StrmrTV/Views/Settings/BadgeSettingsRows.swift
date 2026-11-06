import SwiftUI

/// Settings › Card Badges rows for this device's overrides (`BadgeSettingsStore`): each has
/// "Default (…)", the profile's value, then On and Off. Progress bars always show.
struct BadgeSettingsRows: View {
    @ObservedObject private var store = BadgeSettingsStore.shared

    private static let onOff: [ChoiceRow<Bool>.Choice] = [
        .init(value: true, name: String(localized: "On")),
        .init(value: false, name: String(localized: "Off")),
    ]

    var body: some View {
        ChoiceRow(title: "Watch State", selection: $store.watchState,
                  defaultValue: store.serverShows(.watchState), choices: Self.onOff)
            .accessibilityHint(Text("Marks watched and in-progress titles on their artwork"))
        ChoiceRow(title: "Release Status", selection: $store.releaseStatus,
                  defaultValue: store.serverShows(.releaseStatus), choices: Self.onOff)
            .accessibilityHint(Text("Marks titles that are coming soon, unreleased or in theaters"))
        ChoiceRow(title: "Unwatched Count", selection: $store.unwatchedCount,
                  defaultValue: store.serverShows(.unwatchedCount), choices: Self.onOff)
            .accessibilityHint(Text("Series: episodes left to watch"))
    }
}
