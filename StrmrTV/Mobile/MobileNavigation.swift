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
    }
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
