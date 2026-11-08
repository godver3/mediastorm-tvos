#if os(iOS) && DEBUG
import SwiftUI

/// DEBUG-only prototypes of the details page's Play / Resume area, picked with the launch
/// argument `-StrmrPlayPrototype 1…4` (absent: the current design, `primaryRow`). Each covers
/// a fresh title (Play) and one with progress (Resume, the time left, Start Over). Once one
/// is chosen it replaces `primaryRow` and this file goes.
enum PlayPrototype: Int, CaseIterable {
    /// A regular-size white capsule on the left, the time left and a short bar beside it,
    /// Start Over a small glass circle at the trailing edge.
    case compactPill = 1
    /// Resume (white, prominent) and a labelled glass Start Over side by side, one line
    /// each, with a thin bar and the time left under the pair.
    case split = 2
    /// One accent Liquid Glass capsule the width of the page whose fill is the progress,
    /// the time left in its label; Start Over a glass circle.
    case progressFill = 3
    /// A round white play button with the title's state as text beside it (Podcasts / Music
    /// style), Start Over a glass circle.
    case playRow = 4

    static var selected: PlayPrototype? {
        PlayPrototype(rawValue: UserDefaults.standard.integer(forKey: "StrmrPlayPrototype"))
    }
}

extension MobileDetailsView {
    @ViewBuilder
    func playPrototype(_ variant: PlayPrototype) -> some View {
        let primary = model.primaryTarget
        let resuming = primary?.start != nil
        let fraction = resuming ? model.resumeFraction(primary?.episode) : 0
        let left = resuming ? remainingLabel(primary?.episode) : nil
        let label = primary?.label ?? String(localized: "Play")
        Group {
            switch variant {
            case .compactPill: compactPill(label: label, fraction: fraction, left: left, resuming: resuming)
            case .split: split(label: label, fraction: fraction, left: left, resuming: resuming)
            case .progressFill: progressFill(label: label, fraction: fraction, left: left, resuming: resuming)
            case .playRow: playRow(label: label, fraction: fraction, left: left, resuming: resuming)
            }
        }
        .disabled(primary == nil || model.title == nil)
    }

    // MARK: 1. Compact pill

    private func compactPill(label: String, fraction: Double, left: String?, resuming: Bool) -> some View {
        HStack(spacing: 12) {
            Button { model.playPrimary() } label: {
                Label(label, systemImage: "play.fill").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .modifier(WhiteProminent())
            .controlSize(.regular)
            if resuming {
                VStack(alignment: .leading, spacing: 5) {
                    if let left { Text(left).font(.caption).foregroundStyle(.secondary) }
                    PrototypeBar(fraction: fraction).frame(width: 72)
                }
                Spacer(minLength: 0)
                startOverCircle(size: .regular)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 2. Split Resume | Start Over

    private func split(label: String, fraction: Double, left: String?, resuming: Bool) -> some View {
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
                    PrototypeBar(fraction: fraction)
                    if let left { Text(left).font(.caption).foregroundStyle(.secondary).fixedSize() }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: 3. Progress-filled glass capsule

    private func progressFill(label: String, fraction: Double, left: String?, resuming: Bool) -> some View {
        HStack(spacing: 10) {
            Button { model.playPrimary() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text(label)
                    if let left { Text("· \(left)").foregroundStyle(.white.opacity(0.75)) }
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .modifier(AccentProminent())
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .overlay {
                if fraction > 0 {
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.22))
                            .frame(width: max(geo.size.height, geo.size.width * fraction))
                    }
                    .clipShape(Capsule())
                    .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            if resuming { startOverCircle(size: .large) }
        }
    }

    // MARK: 4. Play row

    private func playRow(label: String, fraction: Double, left: String?, resuming: Bool) -> some View {
        HStack(spacing: 14) {
            Button { model.playPrimary() } label: {
                Image(systemName: "play.fill").font(.title3).frame(width: 34, height: 34)
            }
            .modifier(WhiteProminent())
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel(Text(label))
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.headline)
                if resuming {
                    HStack(spacing: 8) {
                        PrototypeBar(fraction: fraction).frame(width: 90)
                        if let left { Text(left).font(.caption).foregroundStyle(.secondary) }
                    }
                } else if let runtime = runtimeLabel {
                    Text(runtime).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if resuming { startOverCircle(size: .large) }
        }
    }

    // MARK: Shared

    private func startOverCircle(size: ControlSize) -> some View {
        Button { model.play(model.primaryTarget?.episode, from: nil) } label: {
            Image(systemName: "arrow.counterclockwise").font(.subheadline.weight(.semibold))
                .padding(.vertical, size == .large ? 6 : 2)
        }
        .modifier(MobileSecondaryActionStyle())
        .buttonBorderShape(.circle)
        .controlSize(size)
        .accessibilityLabel("Start Over")
    }

    /// "42 min left" from the resume point (exact position, else the percentage).
    private func remainingLabel(_ episode: Episode?) -> String? {
        guard let state = prototypeResumeState(episode), state.eligible else { return nil }
        if state.duration > 0, state.position > 0 {
            let left = max(state.duration - state.position, 60)
            let text = Duration.seconds(left).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
            return String(localized: "\(text) left")
        }
        guard state.percent > 0 else { return nil }
        return String(localized: "\(Int((100 - state.percent).rounded()))% left")
    }

    /// The same resume state `resumeFraction` reads.
    private func prototypeResumeState(_ episode: Episode?) -> ResumeState? {
        guard let episode else { return model.resume }
        if let own = episode.resume { return own }
        if let upNext = model.upNext, DetailsView.isUpNext(episode, upNext) { return model.resume }
        return nil
    }

    private var runtimeLabel: String? {
        let minutes = target.isMovie ? model.title?.runtimeMinutes : model.activeEpisode?.runtimeMinutes
        guard let minutes, minutes > 0 else { return nil }
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// A thin capsule progress bar on a translucent track.
private struct PrototypeBar: View {
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

/// The current Play button's white prominent capsule with black text.
private struct WhiteProminent: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(.white).foregroundStyle(.black)
    }
}

/// The accent color as Liquid Glass (iOS 26), else a bordered prominent capsule.
private struct AccentProminent: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(.accentColor).foregroundStyle(.white)
        } else {
            content.buttonStyle(.borderedProminent).tint(.accentColor).foregroundStyle(.white)
        }
    }
}
#endif
