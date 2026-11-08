#if os(iOS)
import SwiftUI

/// Placeholder until the Library screen is ported.
struct MobileLibraryShowView: View {
    let target: LibraryShowTarget

    var body: some View {
        MobilePendingScreen(title: "Library", systemImage: "books.vertical")
    }
}
#endif
