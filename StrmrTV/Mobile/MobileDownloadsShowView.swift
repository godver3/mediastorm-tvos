#if os(iOS)
import SwiftUI

/// One show's finished downloads, a section per season with the episodes in order (the Expo
/// screen's expanded show). Tap plays, swipe deletes, Edit deletes several.
struct MobileDownloadsShowView: View {
    let titleID: String
    let name: String

    @ObservedObject private var manager = DownloadManager.shared
    @StateObject private var prompts = MobileDownloadsPrompts()
    @State private var selection: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @Environment(\.dismiss) private var dismiss

    private var episodes: [DownloadItem] {
        manager.completed.filter { $0.isEpisode && $0.showKey == titleID }
    }

    private var seasons: [(number: Int, episodes: [DownloadItem])] {
        Dictionary(grouping: episodes) { $0.seasonNumber ?? 0 }
            .map { ($0.key, $0.value.sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }) }
            .sorted { $0.number < $1.number }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(seasons, id: \.number) { season in
                Section {
                    ForEach(season.episodes) { item in
                        Button { prompts.play(item) } label: {
                            MobileDownloadRow(item: item, showsSeries: false)
                                .overlay(alignment: .trailing) {
                                    if prompts.checkingResume == item.id { ProgressView() }
                                }
                        }
                        .tint(.primary)
                        .tag(item.id)
                        .modifier(MobileDownloadRowActions(item: item, prompts: prompts))
                    }
                } header: {
                    Text(season.number == 0 ? String(localized: "Specials") : String(localized: "Season \(season.number)"))
                } footer: {
                    Text(DownloadFormat.bytes(season.episodes.reduce(0) { $0 + $1.expectedBytes }))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if editMode.isEditing {
                    Button(role: .destructive) { prompts.confirmDelete(ids: Array(selection)) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selection.isEmpty)
                }
                EditButton()
            }
        }
        .downloadPrompts(prompts) {
            selection = []
            editMode = .inactive
        }
        .onChange(of: episodes.isEmpty) { _, empty in if empty { dismiss() } }
        .animation(.default, value: episodes.map(\.id))
    }
}
#endif
