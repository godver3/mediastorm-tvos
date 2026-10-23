import AetherEngine
import SwiftUI

/// Settings › Playback rows for `AtmosSettingsStore`; Speaker Layout only while heights are kept.
struct AtmosSettingsRows: View {
    @ObservedObject private var store = AtmosSettingsStore.shared

    var body: some View {
        if AtmosSettingsStore.isAvailable {
            ChoiceRow(title: "Atmos Heights", selection: $store.keepHeights, choices: [
                .init(value: true, name: String(localized: "On")),
                .init(value: false, name: String(localized: "Off (Lossless 7.1)")),
            ])
                .accessibilityHint(Text("Keeps TrueHD Atmos and DTS:X heights for an Atmos receiver or soundbar"))
            if store.keepHeights {
                ChoiceRow(title: "Speaker Layout", selection: $store.layout,
                          choices: SpatialSpeakerLayout.allCases.map { .init(value: $0, name: $0.rawValue) })
                    .accessibilityHint(Text("The speakers your receiver or soundbar drives"))
            }
        }
    }
}
