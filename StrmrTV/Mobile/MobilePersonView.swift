#if os(iOS)
import SwiftUI

/// Placeholder until the Person screen is ported.
struct MobilePersonView: View {
    let person: PersonRef

    var body: some View {
        MobilePendingScreen(title: "Person", systemImage: "person")
    }
}
#endif
