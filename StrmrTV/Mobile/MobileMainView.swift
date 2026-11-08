#if os(iOS)
import SwiftUI

/// The signed-in phone app: a tab bar over Home and the profile screen. The other TV tabs
/// (Live, Search, Lists, …) come over as they get phone layouts.
struct MobileMainView: View {
    @StateObject private var watchlist = WatchlistStore()
    @StateObject private var customLists = CustomListsStore()
    @StateObject private var titles = TitleStateStore()
    @State private var homePath = NavigationPath()

    init() {
        HomeViewsStore.shared.configure(profileID: APIClient.shared.profileID)
    }

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack(path: $homePath) {
                    MobileHomeView(store: HomeViewsStore.shared.store(for: HomeViews.all))
                        .navigationDestination(for: DetailsTarget.self) { MobileDetailsView(target: $0) }
                }
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                NavigationStack { MobileProfileView() }
            }
        }
        .environmentObject(watchlist)
        .environmentObject(customLists)
        .environmentObject(titles)
        .task { await watchlist.refresh() }
        .task { await titles.refresh() }
    }
}

/// The current profile, with Switch Profile and Sign Out.
private struct MobileProfileView: View {
    @ObservedObject private var session = AppSession.shared
    @State private var confirmingSignOut = false

    var body: some View {
        List {
            if let profile = session.profile {
                Section {
                    HStack(spacing: 14) {
                        ProfileAvatar(profile: profile, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name).font(.headline)
                            if let host = session.serverURL?.host() {
                                Text(host).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Button("Switch Profile") { Task { await session.switchProfile() } }
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
            }
            Section {
                LabeledContent("Version", value: Config.fullVersion)
            }
        }
        .navigationTitle("Profile")
        .confirmationDialog("Sign out of this server?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { Task { await session.signOut() } }
        }
    }
}
#endif
