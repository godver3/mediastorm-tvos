import Foundation

/// Regional dubs of a language (Québec French, Latin American Spanish, …), as the server's
/// selector (`backend/services/trackselect/region.go`) sees them: a region-tagged preference
/// (`fr-CA`, `es-419`) picks that dub first and falls back to any track of the language.
/// Releases rarely tag these in the container language (both French dubs are usually `fre`),
/// so a track is recognised by a region-tagged language or by its labels ("VFQ",
/// "French (Canadien)", "FR-CA 5.1", "Latino"). Keep it in step with the Go code.
enum RegionalAudio {
    struct Variant: Equatable {
        let language: String
        let regions: Set<String>
        let words: Set<String>
        let name: String
    }

    private static let variants: [Variant] = [
        Variant(language: "fr", regions: ["ca", "qc"],
                words: ["vfq", "vq", "quebec", "quebecois", "quebecoise", "canada", "canadian", "canadien", "canadienne"],
                name: "French (Canada)"),
        Variant(language: "fr", regions: ["fr", "be", "ch"], words: ["vff", "vfi", "france", "parisian"],
                name: "French (France)"),
        Variant(language: "pt", regions: ["br"], words: ["brazil", "brazilian", "brasil", "brasileiro", "ptbr"],
                name: "Portuguese (Brazil)"),
        Variant(language: "pt", regions: ["pt"], words: ["portugal", "ptpt", "europeu"], name: "Portuguese (Portugal)"),
        Variant(language: "es", regions: ["419", "mx", "latam", "la", "ar", "co", "cl", "us"],
                words: ["latino", "latin", "latam", "latinoamerica", "latinoamericano", "mexico", "mexican", "neutro"],
                name: "Spanish (Latin America)"),
        Variant(language: "es", regions: ["es"], words: ["castilian", "castellano", "spain", "espana", "iberian"],
                name: "Spanish (Spain)"),
    ]

    /// Settings › Audio Language's regional choices, each after its language.
    static let options: [(code: String, name: String)] = [
        ("fr-CA", "French (Canada)"), ("fr-FR", "French (France)"),
        ("es-419", "Spanish (Latin America)"), ("es-ES", "Spanish (Spain)"),
        ("pt-BR", "Portuguese (Brazil)"), ("pt-PT", "Portuguese (Portugal)"),
    ]

    private static func split(_ tag: String?) -> (language: String, region: String) {
        let t = (tag ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard let i = t.firstIndex(where: { $0 == "-" || $0 == "_" }), i != t.startIndex else { return (t, "") }
        return (String(t[..<i]), String(t[t.index(after: i)...]))
    }

    /// The variant a preference such as `fr-CA` asks for; nil for a plain language.
    static func variant(_ preference: String?) -> Variant? {
        let (language, region) = split(preference)
        guard !region.isEmpty else { return nil }
        let code = TrackPreferences.normalize(language)
        return variants.first { $0.language == code && $0.regions.contains(region) }
    }

    /// Whether two preferences ask for the same regional dub (or both for none).
    static func sameVariant(_ a: String?, _ b: String?) -> Bool { variant(a) == variant(b) }

    static func matches(_ variant: Variant, language: String?, title: String?) -> Bool {
        let region = split(language).region
        if !region.isEmpty, variant.regions.contains(region) { return true }
        let label = ((language ?? "") + " " + (title ?? "")).lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
        let words = label.split { !("a"..."z").contains($0) }.map(String.init)
        return words.indices.contains { i in
            // A region right after its language ("FR-CA", "French CA", a "CA" title on a "fre" track).
            variant.words.contains(words[i])
                || (i > 0 && variant.regions.contains(words[i]) && languageCode(words[i - 1]) == variant.language)
        }
    }

    /// `fre` / `fr` / `french` as `fr`.
    private static func languageCode(_ word: String) -> String {
        if let code = ManualTrackSelection.canonicalLanguage(word) { return TrackPreferences.normalize(code) }
        return TrackPreferences.normalize(word)
    }
}
