#if os(iOS)
import SwiftUI

/// The Downloads pages' prompts: Delete (one download, a show's or a selection) and, before a
/// finished download plays, Resume / Start Over when the server has a resume point for it.
@MainActor
final class MobileDownloadsPrompts: ObservableObject {
    struct Deletion: Identifiable {
        let id = UUID()
        let ids: [String]
        let title: String
    }

    struct Resume: Identifiable {
        let id = UUID()
        let item: DownloadItem
        let start: StartPoint
    }

    @Published var deletion: Deletion?
    @Published var resume: Resume?
    @Published var checkingResume: String?

    func play(_ item: DownloadItem) {
        guard checkingResume == nil else { return }
        checkingResume = item.id
        Task {
            let start = await DownloadPlayback.resumePoint(item)
            checkingResume = nil
            if let start {
                resume = Resume(item: item, start: start)
            } else {
                DownloadPlayback.play(item, from: nil)
            }
        }
    }

    func confirmDelete(_ item: DownloadItem) {
        deletion = Deletion(ids: [item.id], title: item.isActive ? String(localized: "Cancel this download?")
                                                                 : String(localized: "Delete “\(item.displayTitle)”?"))
    }

    func confirmDelete(ids: [String]) {
        guard !ids.isEmpty else { return }
        deletion = Deletion(ids: ids, title: ids.count == 1 ? String(localized: "Delete 1 download?")
                                                            : String(localized: "Delete \(ids.count) downloads?"))
    }
}

struct MobileDownloadsPromptsModifier: ViewModifier {
    @ObservedObject var prompts: MobileDownloadsPrompts
    var onDeleted: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .confirmationDialog(prompts.deletion?.title ?? "",
                                isPresented: Binding(get: { prompts.deletion != nil },
                                                     set: { if !$0 { prompts.deletion = nil } }),
                                titleVisibility: .visible, presenting: prompts.deletion) { deletion in
                Button("Delete", role: .destructive) {
                    withAnimation { DownloadManager.shared.delete(deletion.ids) }
                    onDeleted()
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The file is removed from this device.")
            }
            .confirmationDialog(prompts.resume?.item.displayTitle ?? "",
                                isPresented: Binding(get: { prompts.resume != nil },
                                                     set: { if !$0 { prompts.resume = nil } }),
                                titleVisibility: .visible, presenting: prompts.resume) { resume in
                Button("Resume from \(resume.start.label)") { DownloadPlayback.play(resume.item, from: resume.start) }
                Button("Start Over") { DownloadPlayback.play(resume.item, from: nil) }
                Button("Cancel", role: .cancel) {}
            }
    }
}

extension View {
    func downloadPrompts(_ prompts: MobileDownloadsPrompts, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(MobileDownloadsPromptsModifier(prompts: prompts, onDeleted: onDeleted))
    }
}

/// Swipe and context-menu actions for one download row.
struct MobileDownloadRowActions: ViewModifier {
    let item: DownloadItem
    let prompts: MobileDownloadsPrompts

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { prompts.confirmDelete(item) } label: {
                    Label("Delete", systemImage: "trash")
                }
                switch item.status {
                case .downloading, .pending:
                    Button { DownloadManager.shared.pause(item.id) } label: { Label("Pause", systemImage: "pause") }
                        .tint(.orange)
                case .paused, .failed:
                    Button { DownloadManager.shared.resume(item.id) } label: {
                        Label("Resume", systemImage: "arrow.down")
                    }
                    .tint(.blue)
                case .completed:
                    EmptyView()
                }
            }
            .contextMenu {
                switch item.status {
                case .completed:
                    Button { prompts.play(item) } label: { Label("Play", systemImage: "play.fill") }
                case .downloading, .pending:
                    Button { DownloadManager.shared.pause(item.id) } label: { Label("Pause", systemImage: "pause") }
                case .paused:
                    Button { DownloadManager.shared.resume(item.id) } label: { Label("Resume", systemImage: "arrow.down") }
                case .failed:
                    Button { DownloadManager.shared.resume(item.id) } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
                if let release = item.releaseName {
                    Text(release)
                }
                Button(role: .destructive) { prompts.confirmDelete(item) } label: {
                    Label(item.isActive ? "Cancel Download" : "Delete Download", systemImage: "trash")
                }
            }
    }
}
#endif
