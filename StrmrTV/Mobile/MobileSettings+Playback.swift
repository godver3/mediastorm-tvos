#if os(iOS)
import AetherEngine
import SwiftUI

/// Settings › Playback on the phone: the TV's Playback rows (track overrides, audio format,
/// Atmos heights, Auto Switch Sources) over the same stores, so a choice made here is the one
/// the shared player reads, and the phone's player orientation. Expo's phone "Prefer TrueHD" is Audio Format › Lossless.
struct MobilePlaybackSettingsView: View {
    @ObservedObject private var tracks = TrackSettingsStore.shared
    @ObservedObject private var atmos = AtmosSettingsStore.shared
    @ObservedObject private var autoSwitch = AutoSwitchSettingsStore.shared
    @ObservedObject private var credits = CreditsDetectionSettingsStore.shared
    @AppStorage(PhonePlayerOrientation.defaultsKey) private var orientation: PhonePlayerOrientation = .landscape

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
        Form {
            Section {
                MobileOverridePicker("Subtitles", selection: $tracks.subtitleMode,
                                     defaultValue: tracks.server.subtitleMode ?? "off", choices: [
                                         .init(value: "off", name: String(localized: "Off")),
                                         .init(value: "forced-only", name: String(localized: "Forced Only")),
                                         .init(value: ClientTrackSelector.foreignAudio, name: String(localized: "Foreign Audio")),
                                         .init(value: "on", name: String(localized: "On")),
                                     ])
                MobileOverridePicker("Subtitle Language", selection: $tracks.subtitleLanguage,
                                     defaultValue: canonical(tracks.server.subtitleLanguage),
                                     choices: Self.languages, style: .navigationLink)
                if tracks.server.translationEnabled == false {
                    // The server's switch is the admin's: a device can turn translation off, never on.
                    LabeledContent("Subtitle Translation", value: String(localized: "Off (disabled on server)"))
                } else {
                    MobileOverridePicker("Subtitle Translation", selection: $tracks.translation,
                                         defaultValue: tracks.server.translationEnabled ?? true,
                                         choices: MobileChoices.onOff)
                }
                NavigationLink {
                    MobileSubtitleStyleView()
                } label: {
                    Text("Subtitle Style")
                }
            } header: {
                Text("Subtitles")
            } footer: {
                Text("Foreign Audio shows forced subtitles for audio in your language and full ones for any other. Translation translates English subtitles when none are in your language.")
            }

            Section {
                MobileOverridePicker("Audio Language", selection: $tracks.audioLanguage,
                                     defaultValue: canonicalAudio(tracks.server.audioLanguage),
                                     choices: Self.audioLanguages, style: .navigationLink)
                MobileOverridePicker("Audio Format", selection: $tracks.losslessAudio, choices: [
                    .init(value: false, name: String(localized: "Compatible (E-AC-3)")),
                    .init(value: true, name: String(localized: "Lossless (TrueHD)")),
                ])
                if AtmosSettingsStore.isAvailable {
                    Toggle("Atmos Heights", isOn: $atmos.keepHeights)
                    if atmos.keepHeights {
                        MobileOverridePicker("Speaker Layout", selection: $atmos.layout,
                                             choices: SpatialSpeakerLayout.allCases.map { .init(value: $0, name: $0.rawValue) })
                    }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text(audioFooter)
            }

            if UIDevice.current.userInterfaceIdiom == .phone {
                Section {
                    MobileOverridePicker("Player Orientation", selection: $orientation,
                                         choices: PhonePlayerOrientation.allCases.map { .init(value: $0, name: $0.title) })
                } footer: {
                    Text("Follow Device Rotation starts the player the way the phone is held and turns with it.")
                }
            }

            Section {
                Toggle("Auto Switch Sources", isOn: $autoSwitch.enabled)
            } footer: {
                Text("Moves to another source when the current one fails or keeps stalling.")
            }

            Section {
                MobileOverridePicker("Credits Detection", selection: $credits.override,
                                     defaultValue: credits.serverValue ?? false, choices: MobileChoices.onOff)
            } footer: {
                Text("When no credits are known for an episode, reads the end of the episode for credit text to offer Next Episode.")
            }
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await tracks.refresh() }
        .task { await credits.refresh() }
    }

    private var audioFooter: LocalizedStringKey {
        AtmosSettingsStore.isAvailable
            ? "Audio Format picks which track starts when a source has several in your language. Atmos Heights keeps TrueHD Atmos and DTS:X heights for spatial audio; off, they play as lossless 7.1."
            : "Audio Format picks which track starts when a source has several in your language."
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
#endif
