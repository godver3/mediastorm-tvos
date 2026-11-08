#if os(iOS)
import SwiftUI

/// What tapping a card does, around its face: a title opens details (long press: the title
/// actions, `TitleActionsMenu`, as the Expo long-press menu); a list opens the list page; a
/// Watch Something card runs its action; a favorite channel tunes in; a library title opens
/// or plays (`LibraryEntryLink`).
struct MobileCardLink<Label: View>: View {
    let card: HomeCard
    var onHide: (() -> Void)?
    var onRemoveFromList: (() -> Void)?
    @ViewBuilder let label: Label

    var body: some View {
        switch card.link {
        case let .details(target):
            NavigationLink(value: target) { label }
                .buttonStyle(.plain)
                .contextMenu {
                    TitleActionsMenu(target: target, episode: card.episode, onHideFromContinueWatching: onHide,
                                     onRemoveFromList: onRemoveFromList)
                }
                .accessibilityLabel("\(card.title), \(card.subtitle)")
        case let .list(list):
            NavigationLink(value: list) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(card.title)
        case let .action(action):
            MobileHomeActionButton(action: action) { label }
                .accessibilityLabel(card.title)
        case let .channel(channel, program):
            Button { LivePlayback.play(channel, program: program) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.title), \(card.subtitle)")
        case let .library(entry):
            LibraryEntryLink(entry: entry) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(card.title), \(card.subtitle)")
        }
    }
}

/// A Watch Something card's button; Home sets the action (`\.homeAction`).
private struct MobileHomeActionButton<Label: View>: View {
    let action: HomeAction
    @ViewBuilder let label: Label
    @Environment(\.homeAction) private var homeAction

    var body: some View {
        Button { homeAction(action) } label: { label }.buttonStyle(.plain)
    }
}

extension View {
    /// The modals a card's long press opens over every tab (Manage Lists… and the series
    /// watch-state dialogs) and the title store's toast. Applied once, on the tab view.
    func mobileLongPressModals(customLists: CustomListsStore, titles: TitleStateStore) -> some View {
        modifier(MobileLongPressModals(customLists: customLists, titles: titles))
    }
}

private struct MobileLongPressModals: ViewModifier {
    @ObservedObject var customLists: CustomListsStore
    @ObservedObject var titles: TitleStateStore
    @State private var watchState: WatchStateRequest?

    func body(content: Content) -> some View {
        content
            .task(id: titles.watchStateTarget?.titleID) { await loadWatchState() }
            .watchStateDialogs($watchState, isWatched: { $0.watched == true }) {
                await titles.seriesWatchStateChanged()
            }
            .environmentObject(titles)
            .onChange(of: watchState?.id) { _, id in
                if id == nil { titles.watchStateTarget = nil }
            }
            .sheet(item: $customLists.picking) { target in
                MobileAddToListSheet(target: target).environmentObject(customLists)
            }
            .overlay { MobileToast().environmentObject(titles) }
    }

    private func loadWatchState() async {
        guard let series = titles.watchStateTarget else { return }
        do {
            guard let seasons = try await APIClient.shared.detailsBundle(series).seriesDetails?.seasons else {
                throw APIError.notReady("Details unavailable")
            }
            guard titles.watchStateTarget?.titleID == series.titleID else { return }
            watchState = WatchStateRequest(series: series, seasons: seasons)
        } catch {
            titles.log.error("watch state for \(series.titleID) failed: \(error.localizedDescription)")
            titles.show(toast: String(localized: "Failed to load episodes"))
            titles.watchStateTarget = nil
        }
    }
}

/// The title store's confirmation, over the tab bar.
private struct MobileToast: View {
    @EnvironmentObject private var titles: TitleStateStore

    var body: some View {
        VStack {
            Spacer()
            if let text = titles.toast {
                Label(text, systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("titleToast")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 64)
        .animation(.easeOut(duration: 0.2), value: titles.toast)
        .allowsHitTesting(false)
    }
}

/// "Manage Lists…": each of the profile's lists, checked where it holds the title. Tapping
/// a list adds or removes the title in place; New List… creates one with the title in it.
struct MobileAddToListSheet: View {
    @EnvironmentObject private var store: CustomListsStore
    @Environment(\.dismiss) private var dismiss
    let target: DetailsTarget

    @State private var memberships: [String: WatchlistItem]?
    @State private var busy: Set<String> = []
    @State private var error: String?
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).foregroundStyle(.red)
                }
                Section {
                    if memberships == nil {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        ForEach(store.userLists) { row($0) }
                    }
                }
                Section {
                    Button {
                        newName = ""
                        naming = true
                    } label: {
                        Label("New List…", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Manage Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Manage Lists").font(.headline)
                        Text(target.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                await store.refresh()
                memberships = await store.memberships(of: target)
            }
            .alert("New List", isPresented: $naming) {
                TextField("Name", text: $newName)
                Button("Create and Add") { Task { await createAndAdd() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The new list will start with \(target.name).")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ list: CustomList) -> some View {
        let isMember = memberships?[list.id] != nil
        return Button {
            Task { await toggle(list) }
        } label: {
            HStack {
                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isMember ? Color.accentColor : .secondary)
                    .imageScale(.large)
                Text(list.name).foregroundStyle(.primary)
                Spacer()
                if busy.contains(list.id) {
                    ProgressView()
                } else if let count = list.itemCount {
                    Text("\(count)").foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
        .disabled(busy.contains(list.id))
        .accessibilityValue(isMember ? Text("In list") : Text("Not in list"))
    }

    private func toggle(_ list: CustomList) async {
        guard !busy.contains(list.id) else { return }
        busy.insert(list.id)
        defer { busy.remove(list.id) }
        do {
            if let item = memberships?[list.id] {
                try await store.remove(item, from: list.id)
                memberships?[list.id] = nil
            } else {
                try await store.add(target, to: list.id)
                memberships = await store.memberships(of: target)
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = store.nameProblem(name) {
            error = problem
            return
        }
        do {
            let list = try await store.create(name: name)
            try await store.add(target, to: list.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
