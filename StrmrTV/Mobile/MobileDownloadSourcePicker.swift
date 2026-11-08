#if os(iOS)
import SwiftUI

/// Choose a release to download, as the Expo manual picker in download mode: the indexer
/// results ranked for downloading (`downloadRanking`), with their health and size. For a
/// season, only packs covering the whole season are offered, since every episode is taken
/// from the one release. A tap hands the result back; resolving and queuing happen after.
struct MobileDownloadSourcePicker: View {
    let request: MobileDetailsModel.DownloadRequest
    let onPick: (SourceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var results: [SourceResult] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Searching sources…").foregroundStyle(.secondary)
                        }
                    } else if let error {
                        ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    } else if results.isEmpty {
                        ContentUnavailableView(request.season == nil ? "No Sources Found" : "No Season Packs Found",
                                               systemImage: "magnifyingglass")
                    } else {
                        ForEach(results, id: \.index) { result in
                            Button {
                                dismiss()
                                onPick(result)
                            } label: {
                                SourceRow(result: result, health: result.health)
                            }
                            .tint(.primary)
                        }
                    }
                } header: {
                    if !isLoading, !results.isEmpty { Text(header) }
                } footer: {
                    if !isLoading, !results.isEmpty, let free = DownloadStorage.availableBytes {
                        Text("\(DownloadFormat.bytes(free)) available on this \(UIDevice.current.localizedModel).")
                    }
                }
            }
            .navigationTitle(request.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .task { await load() }
    }

    private var header: String {
        if let season = request.season {
            return String(localized: "Packs for all \(season.episodes.count) episodes")
        }
        return results.count == 1 ? String(localized: "1 source") : String(localized: "\(results.count) sources")
    }

    private func load() async {
        let target = request.target
        let query: String
        if let season = request.season {
            query = target.name + String(format: " S%02d", season.number)
        } else {
            query = SourceSearch.query(name: target.name, year: target.year,
                                       episode: request.episode.map { ($0.seasonNumber, $0.episodeNumber) })
        }
        do {
            results = SourceSearch.ordered(try await APIClient.shared.downloadSources(
                query: query, title: target, numbering: request.episode?.numbering,
                seasonPacksOnly: request.season != nil))
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
#endif
