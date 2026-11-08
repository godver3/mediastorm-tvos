#if os(iOS)
import SwiftUI

/// Placeholder until the Calendar screen is ported.
struct MobileCalendarView: View {
    var body: some View {
        MobilePendingScreen(title: "Calendar", systemImage: "calendar")
    }
}
#endif
