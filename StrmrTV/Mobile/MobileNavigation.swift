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
