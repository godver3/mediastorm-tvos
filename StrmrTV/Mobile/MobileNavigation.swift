#if os(iOS)
import SwiftUI

/// The pages any phone tab can push, registered once per NavigationStack. Each value type
/// maps to the phone screen that owns it.
extension View {
    func mobileDestinations() -> some View {
        navigationDestination(for: DetailsTarget.self) { MobileDetailsView(target: $0) }
            .navigationDestination(for: PersonRef.self) { MobilePersonView(person: $0) }
            .navigationDestination(for: BrowseList.self) { MobileListPage(list: $0) }
            .navigationDestination(for: LibraryShowTarget.self) { MobileLibraryShowView(target: $0) }
            .navigationDestination(for: MobileSearchRoute.self) { _ in MobileSearchView() }
    }
}

/// Search as a pushed page (Home's Watch Something Search card).
struct MobileSearchRoute: Hashable {}

extension EnvironmentValues {
    /// Pushes a page onto Home's path-backed stack. Home's own pushes go through the path:
    /// a `navigationDestination(isPresented:)` page in a path-backed stack is rebuilt when a
    /// value link on it appends to the path, so a title tapped in Search reopened Search.
    @Entry var mobilePush: (any Hashable) -> Void = { _ in }
}

/// An empty, failed or loading state inside a scroll view, rather than in an overlay on
/// it: pull to refresh still works on it, and it is given the scroll view's full width
/// (in an overlay a `ContentUnavailableView` could be laid out a letter or two wide).
struct MobileScrollStatus<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                axis == .vertical ? length * 0.8 : length
            }
    }
}

/// A screen not ported to the phone yet.
struct MobilePendingScreen: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming to iPhone soon."))
            .navigationTitle(title)
    }
}
#endif
