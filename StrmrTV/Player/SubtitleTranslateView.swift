import SwiftUI

/// The player's Translate… page, as the Expo app's track modal translate mode: first the
/// subtitle track to translate (text tracks in the file), then the language to translate it
/// into (the player languages the profile allows, as Search Online… lists them). Menu on the
/// language step goes back to the tracks; on the tracks it closes.
struct SubtitleTranslateView: View {
    /// One translatable track, labelled as in the Subtitles menu.
    struct Source: Identifiable {
        let id: Int
        let title: String
        let detail: String
    }

    let heading: String
    let sources: [Source]
    let onPick: (_ source: Int, _ language: SubtitleSearchModel.Language) -> Void
    let onClose: () -> Void

    @State private var picked: Source?
    @State private var languages: [SubtitleSearchModel.Language] = []

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Translate Subtitles").font(.title2.weight(.semibold))
                    Text(picked.map { String(localized: "Translate \($0.title) into…") }
                        ?? String(localized: "Choose the subtitles to translate"))
                        .font(.callout).foregroundStyle(.secondary)
                    Text(heading).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)

                if let picked {
                    languageList(for: picked)
                } else {
                    sourceList
                }
            }
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .background(Color.black.ignoresSafeArea())
        .onExitCommand {
            if picked != nil { picked = nil } else { onClose() }
        }
        .task { languages = await SubtitleSearchModel.allowedLanguages() }
    }

    @ViewBuilder private var sourceList: some View {
        if sources.isEmpty {
            Text("No subtitle tracks in this video can be translated")
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(sources) { source in
                    Button { picked = source } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(source.title).font(.callout)
                            Text(source.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(SourceRowStyle())
                }
            }
        }
    }

    @ViewBuilder private func languageList(for source: Source) -> some View {
        if languages.isEmpty {
            ProgressView()
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(languages, id: \.self) { language in
                    Button { onPick(source.id, language) } label: {
                        Text(Locale.current.localizedString(forLanguageCode: language.code) ?? language.name)
                            .font(.callout)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(SourceRowStyle())
                }
            }
        }
    }
}
