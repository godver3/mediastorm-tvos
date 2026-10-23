import SwiftUI

/// The player's Search Online… page, as the Expo app's `SubtitleSearchModal`: a row of
/// languages (the player languages the profile allows), then the provider results for the
/// chosen one, closest release first. Picking a result hands it back; Menu closes.
@MainActor
final class SubtitleSearchModel: ObservableObject {
    /// The Expo player's `PLAYER_LANGUAGE_OPTIONS`.
    struct Language: Hashable {
        let code: String
        let settingCode: String
        let name: String
    }

    static let options: [Language] = [
        ("en", "eng", "English"), ("fr", "fra", "French"), ("es", "spa", "Spanish"), ("de", "deu", "German"),
        ("it", "ita", "Italian"), ("pt", "por", "Portuguese"), ("nl", "nld", "Dutch"), ("pl", "pol", "Polish"),
        ("ru", "rus", "Russian"), ("ja", "jpn", "Japanese"), ("ko", "kor", "Korean"), ("zh", "zho", "Chinese"),
        ("ar", "ara", "Arabic"), ("he", "heb", "Hebrew"), ("sv", "swe", "Swedish"), ("no", "nor", "Norwegian"),
        ("da", "dan", "Danish"), ("fi", "fin", "Finnish"), ("hr", "hrv", "Croatian"), ("sr", "srp", "Serbian"),
        ("bs", "bos", "Bosnian"),
    ].map { Language(code: $0.0, settingCode: $0.1, name: $0.2) }

    @Published private(set) var languages: [Language] = []
    @Published private(set) var language: Language?
    @Published private(set) var results: [SubtitleSearchResult] = []
    @Published private(set) var isLoading = true
    @Published private(set) var error: String?

    private let preferredLanguage: String?
    private let releaseName: String?
    private let search: (String) async throws -> [SubtitleSearchResult]
    private var searchTask: Task<Void, Never>?

    init(preferredLanguage: String?, releaseName: String?,
         search: @escaping (String) async throws -> [SubtitleSearchResult]) {
        self.preferredLanguage = preferredLanguage
        self.releaseName = releaseName
        self.search = search
    }

    /// Filters the languages by the profile's allowed list, then searches the preferred
    /// subtitle language (else the first allowed one).
    func load() async {
        languages = await Self.allowedLanguages()
        let preferred = preferredLanguage.flatMap { code in languages.first { Self.sameLanguage(code, $0) } }
        select(preferred ?? languages[0])
    }

    func select(_ next: Language) {
        guard next != language || error != nil else { return }
        language = next
        isLoading = true
        error = nil
        results = []
        searchTask?.cancel()
        searchTask = Task { [weak self, search, releaseName] in
            do {
                let found = try await search(next.code)
                // A newer language pick supersedes this one.
                guard let self, !Task.isCancelled, language == next else { return }
                results = OnlineSubtitleMatching.sortedForList(found, releaseName: releaseName)
                isLoading = false
            } catch {
                guard let self, !Task.isCancelled, language == next else { return }
                self.error = String(localized: "Failed to search for subtitles")
                isLoading = false
            }
        }
    }

    func cancel() { searchTask?.cancel() }

    /// `options` the profile's `allowedTrackLanguages` allow (all when it allows everything,
    /// or nothing in the list would remain). Also Translate…'s target list.
    static func allowedLanguages() async -> [Language] {
        let allowed = await APIClient.shared.allowedTrackLanguages()
        let filtered = options.filter { option in
            allowed.isEmpty || allowed.contains { sameLanguage($0, option) }
        }
        return filtered.isEmpty ? options : filtered
    }

    private static func sameLanguage(_ tag: String, _ option: Language) -> Bool {
        tag.lowercased() == option.name.lowercased() || TrackPreferences.sameLanguage(tag, option.settingCode)
    }
}

struct SubtitleSearchView: View {
    @ObservedObject var model: SubtitleSearchModel
    let heading: String
    let onPick: (SubtitleSearchResult, String) -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Subtitles").font(.title2.weight(.semibold))
                    Text(heading).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 12)

                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(model.languages, id: \.self) { language in
                            Button(language.name) { model.select(language) }
                                .buttonStyle(SeasonChipStyle(selected: language == model.language))
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 8)
                }
                .scrollClipDisabled()
                .padding(.bottom, 12)

                content
            }
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        // Opaque: the paused player's HUD and subtitles would show through.
        .background(Color.black.ignoresSafeArea())
        .onExitCommand { onClose() }
        .task { await model.load() }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            HStack(spacing: 24) {
                ProgressView()
                Text("Searching \(model.language?.name ?? "")…").foregroundStyle(.secondary)
            }
        } else if let error = model.error {
            Text(error).foregroundStyle(.secondary)
        } else if model.results.isEmpty {
            Text("No subtitles found for \(model.language?.name ?? "")").foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(model.results) { result in
                    Button {
                        onPick(result, model.language?.code ?? result.language)
                    } label: {
                        SubtitleResultRow(result: result)
                    }
                    .buttonStyle(SourceRowStyle())
                }
            }
        }
    }
}

/// Release name, then the provider, an SDH badge and the download count.
private struct SubtitleResultRow: View {
    let result: SubtitleSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.release.isEmpty ? String(localized: "Unnamed release") : result.release)
                .font(.callout).lineLimit(2)
            HStack(spacing: 12) {
                badge(OnlineSubtitles.providerName(result.provider))
                if result.hearingImpaired { badge("SDH") }
                if result.downloads > 0 {
                    Label(result.downloads.formatted(), systemImage: "arrow.down.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary, lineWidth: 1.5))
    }
}
