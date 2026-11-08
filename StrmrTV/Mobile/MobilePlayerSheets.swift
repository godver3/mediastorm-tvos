#if os(iOS)
import SwiftUI
import UIKit

// The phone player's pages, as sheets over the paused video: Search Online…, Translate…,
// Switch Source and Stream Info. They hold the same models and callbacks as the TV's full-screen
// pages (`SubtitleSearchView`, `SubtitleTranslateView`, `SourceSwitchView`, the Stream tab), laid
// out as iOS lists in a navigation stack with a Done / Cancel button.

/// Search Online…: a language menu in the toolbar, then the provider results, closest release first.
struct MobileSubtitleSearchView: View {
    @ObservedObject var model: SubtitleSearchModel
    let heading: String
    let onPick: (SubtitleSearchResult, String) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    content
                } header: {
                    Text(heading)
                }
            }
            .navigationTitle("Search Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onClose)
                }
                ToolbarItem(placement: .primaryAction) { languageMenu }
            }
        }
        .task { await model.load() }
        .onDisappear { model.cancel() }
    }

    private var languageMenu: some View {
        Menu {
            Picker("Language", selection: Binding(get: { model.language }, set: { $0.map(model.select) })) {
                ForEach(model.languages, id: \.self) { language in
                    Text(language.name).tag(Optional(language))
                }
            }
        } label: {
            Label(model.language?.name ?? String(localized: "Language"), systemImage: "globe")
                .labelStyle(.titleAndIcon)
        }
        .disabled(model.languages.isEmpty)
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("Searching \(model.language?.name ?? "")…").foregroundStyle(.secondary)
            }
        } else if let error = model.error {
            Text(error).foregroundStyle(.secondary)
        } else if model.results.isEmpty {
            Text("No subtitles found for \(model.language?.name ?? "")").foregroundStyle(.secondary)
        } else {
            ForEach(model.results) { result in
                Button {
                    onPick(result, model.language?.code ?? result.language)
                } label: {
                    MobileSubtitleResultRow(result: result)
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

/// Release name, then the provider, an SDH badge and the download count.
private struct MobileSubtitleResultRow: View {
    let result: SubtitleSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.release.isEmpty ? String(localized: "Unnamed release") : result.release)
                .font(.subheadline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(OnlineSubtitles.providerName(result.provider))
                if result.hearingImpaired { Text("SDH").fontWeight(.semibold) }
                if result.downloads > 0 {
                    Label(result.downloads.formatted(), systemImage: "arrow.down.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// Translate…: the text tracks in the file, then (pushed) the language to translate into.
struct MobileSubtitleTranslateView: View {
    let heading: String
    let sources: [SubtitleTranslateView.Source]
    let onPick: (_ source: Int, _ language: SubtitleSearchModel.Language) -> Void
    let onClose: () -> Void

    @State private var languages: [SubtitleSearchModel.Language] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if sources.isEmpty {
                        Text("No subtitle tracks in this video can be translated").foregroundStyle(.secondary)
                    }
                    ForEach(sources) { source in
                        NavigationLink {
                            languageList(for: source)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.title)
                                Text(source.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Choose the subtitles to translate")
                } footer: {
                    Text(heading)
                }
            }
            .navigationTitle("Translate Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onClose)
                }
            }
        }
        .task { languages = await SubtitleSearchModel.allowedLanguages() }
    }

    private func languageList(for source: SubtitleTranslateView.Source) -> some View {
        List {
            if languages.isEmpty { ProgressView() }
            ForEach(languages, id: \.self) { language in
                Button(Locale.current.localizedString(forLanguageCode: language.code) ?? language.name) {
                    onPick(source.id, language)
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(String(localized: "Translate \(source.title) into…"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Switch Source: the ranked sources with the playing one checked.
struct MobileSourceSwitchView: View {
    let heading: String
    let rows: [SourceSwitchView.Row]
    let onPick: (SourceSwitch.Option) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.offset) { position, row in
                            Button {
                                if row.option.isCurrent { onClose() } else { onPick(row.option) }
                            } label: {
                                label(row)
                            }
                            .foregroundStyle(.primary)
                            .id(position)
                        }
                    } header: {
                        Text(heading)
                    } footer: {
                        if !rows.contains(where: { !$0.option.isCurrent }) { Text("No other sources") }
                    }
                }
                .onAppear {
                    if let current = rows.firstIndex(where: { $0.option.isCurrent }) {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
            .navigationTitle("Switch Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel, action: onClose)
                }
            }
        }
    }

    @ViewBuilder private func label(_ row: SourceSwitchView.Row) -> some View {
        if let result = row.result {
            SourceRow(result: result, health: row.health, isCurrent: row.option.isCurrent)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("Playing", systemImage: "checkmark.circle.fill").font(.caption.weight(.bold))
                Text(row.option.title).font(.subheadline).lineLimit(2)
                Text(row.option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Stream Info: the Stream tab's label / value rows.
struct MobileStreamInfoView: View {
    let info: StreamInfo
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if info.rows.isEmpty { Text("No stream details yet").foregroundStyle(.secondary) }
                ForEach(info.rows, id: \.label) { row in
                    LabeledContent(row.label) {
                        Text(row.value).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Stream Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) }
            }
        }
    }
}

extension UIViewController {
    /// A page over the player as a sheet: half height first, full on a drag up (a compact-height
    /// phone in landscape shows sheets full height anyway). `onSwipeDismiss` runs when the viewer
    /// drags it away rather than tapping one of its buttons.
    static func mobilePlayerSheet<Content: View>(_ content: Content,
                                                 onSwipeDismiss: @escaping @MainActor () -> Void) -> UIViewController {
        let host = MobileSheetHost(rootView: content)
        host.onSwipeDismiss = onSwipeDismiss
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.delegate = host
        }
        host.overrideUserInterfaceStyle = .dark
        return host
    }
}

private final class MobileSheetHost<Content: View>: UIHostingController<Content>, UISheetPresentationControllerDelegate {
    var onSwipeDismiss: (@MainActor () -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 560, height: 0)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onSwipeDismiss?()
    }
}
#endif
