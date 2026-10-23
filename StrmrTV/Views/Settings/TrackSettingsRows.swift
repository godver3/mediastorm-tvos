import SwiftUI

/// Settings › Playback rows for this device's track overrides (`TrackSettingsStore`): each
/// has "Default (…)", the profile's value, then choices that override it on this device.
struct TrackSettingsRows: View {
    @ObservedObject private var store = TrackSettingsStore.shared

    private static let languages: [ChoiceRow<String>.Choice] = SubtitleSearchModel.options.map {
        .init(value: $0.settingCode, name: Locale.current.localizedString(forLanguageCode: $0.code) ?? $0.name)
    }

    /// The languages with each regional dub ("French (Canada)") after its language.
    private static let audioLanguages: [ChoiceRow<String>.Choice] = SubtitleSearchModel.options.flatMap { option in
        let base = ChoiceRow<String>.Choice(
            value: option.settingCode, name: Locale.current.localizedString(forLanguageCode: option.code) ?? option.name)
        let regional = RegionalAudio.options.filter { TrackPreferences.sameLanguage($0.code, option.settingCode) }.map {
            ChoiceRow<String>.Choice(value: $0.code, name: Locale.current.localizedString(forIdentifier: $0.code) ?? $0.name)
        }
        return [base] + regional
    }

    var body: some View {
        ChoiceRow(title: "Subtitles", selection: $store.subtitleMode,
                  defaultValue: store.server.subtitleMode ?? "off", choices: [
                      .init(value: "off", name: String(localized: "Off")),
                      .init(value: "forced-only", name: String(localized: "Forced Only")),
                      .init(value: "on", name: String(localized: "On")),
                  ])
            .accessibilityHint(Text("Which subtitles start with playback"))
        ChoiceRow(title: "Subtitle Language", selection: $store.subtitleLanguage,
                  defaultValue: canonical(store.server.subtitleLanguage), choices: Self.languages)
        if store.server.translationEnabled == false {
            // The server's switch is the admin's: a device can turn translation off, never on.
            LabeledContent("Subtitle Translation") {
                Text("Off (disabled on server)")
            }
            .foregroundStyle(.secondary)
        } else {
            ChoiceRow(title: "Subtitle Translation", selection: $store.translation,
                      defaultValue: store.server.translationEnabled ?? true, choices: [
                          .init(value: true, name: String(localized: "On")),
                          .init(value: false, name: String(localized: "Off")),
                      ])
                .accessibilityHint(Text("Translates English subtitles when none are in your language"))
        }
        ChoiceRow(title: "Audio Language", selection: $store.audioLanguage,
                  defaultValue: canonicalAudio(store.server.audioLanguage), choices: Self.audioLanguages)
    }

    /// The profile's code as the list spells it (`fre` → `fra`), so its name shows.
    private func canonical(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return SubtitleSearchModel.options.first { TrackPreferences.sameLanguage($0.settingCode, code) }?.settingCode ?? code
    }

    /// As `canonical`, keeping a regional dub (`fr-ca` → `fr-CA`).
    private func canonicalAudio(_ code: String?) -> String? {
        guard let code, RegionalAudio.variant(code) != nil else { return canonical(code) }
        return RegionalAudio.options.first {
            TrackPreferences.sameLanguage($0.code, code) && RegionalAudio.sameVariant($0.code, code)
        }?.code ?? code
    }
}
