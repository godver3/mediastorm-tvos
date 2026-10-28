import SwiftUI

/// A resume-progress bar along the bottom of a card.
struct ProgressBar: View {
    let fraction: Double

    /// Whether a card shows its resume progress: any started progress under 90% watched.
    /// Whether progress counts as started is the server's call (`ResumeState.eligible`);
    /// callers pass 0 when it doesn't.
    static func shows(_ fraction: Double) -> Bool { fraction > 0 && fraction < 0.9 }

    var body: some View {
        GeometryReader { geo in
            // A dark base under the track, so it reads on bright art as well as on a card's
            // text gradient; the fill is full white with a soft shadow to lift it off both.
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(.white).frame(width: geo.size.width * fraction)
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
        }
        .frame(height: 8)
    }
}
