#if os(iOS)
import SwiftUI

/// The details page's Play / Resume area: a white Play (or Resume) button and, with progress,
/// a labelled glass Start Over beside it and a thin bar with the time left under the pair.
extension MobileDetailsView {
    var primaryRow: some View {
        let primary = model.primaryTarget
        let resuming = primary?.start != nil
        return playButtons(label: primary?.label ?? String(localized: "Play"),
                           fraction: resuming ? model.resumeFraction(primary?.episode) : 0,
                           left: resuming ? remainingLabel(primary?.episode) : nil,
                           resuming: resuming)
            .disabled(primary == nil || model.title == nil)
    }

    private func playButtons(label: String, fraction: Double, left: String?, resuming: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { model.playPrimary() } label: {
                    Label(label, systemImage: "play.fill").font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .modifier(WhiteProminent())
                .layoutPriority(1)
                if resuming {
                    Button { model.play(model.primaryTarget?.episode, from: nil) } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .modifier(MobileSecondaryActionStyle())
                    .buttonBorderShape(.capsule)
                    .frame(width: 140)
                }
            }
            .controlSize(.large)
            if resuming {
                HStack(spacing: 10) {
                    ResumeBar(fraction: fraction)
                    if let left { Text(left).font(.caption).foregroundStyle(.secondary).fixedSize() }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// "42 min left" from the resume point (exact position, else the percentage).
    private func remainingLabel(_ episode: Episode?) -> String? {
        guard let state = resumeState(episode), state.eligible else { return nil }
        if state.duration > 0, state.position > 0 {
            let left = max(state.duration - state.position, 60)
            let text = Duration.seconds(left).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            return String(localized: "\(text) left")
        }
        guard state.percent > 0 else { return nil }
        return String(localized: "\(Int((100 - state.percent).rounded()))% left")
    }

    /// The same resume state `resumeFraction` reads.
    private func resumeState(_ episode: Episode?) -> ResumeState? {
        guard let episode else { return model.resume }
        if let own = episode.resume { return own }
        if let upNext = model.upNext, DetailsView.isUpNext(episode, upNext) { return model.resume }
        return nil
    }
}

/// A thin capsule progress bar on a translucent track.
private struct ResumeBar: View {
    let fraction: Double

    var body: some View {
        Capsule().fill(.white.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(.white).frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
    }
}

/// The Play button's white prominent capsule with black text.
private struct WhiteProminent: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.white).foregroundStyle(.black)
    }
}
#endif
