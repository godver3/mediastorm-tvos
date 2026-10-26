import SwiftUI

/// A resume-progress bar along the bottom of a card.
struct ProgressBar: View {
    let fraction: Double

    /// Whether a card shows its resume progress: only between 5% and 90% watched.
    static func shows(_ fraction: Double) -> Bool { fraction > 0.05 && fraction < 0.9 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}
