import SwiftUI

/// A resume-progress bar along the bottom of a card.
struct ProgressBar: View {
    let fraction: Double

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
