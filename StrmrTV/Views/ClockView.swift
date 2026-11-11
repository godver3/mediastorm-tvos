import SwiftUI
import UIKit

/// Settings › Appearance › Show Clock: the time of day in the top-right corner of Home and of the
/// player while its transport bar (or the software route's HUD) is up. Device only; on by
/// default. tvOS only: the iPhone / iPad status bar already shows the time.
@MainActor
final class ClockSettingsStore: ObservableObject {
    static let shared = ClockSettingsStore()

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Self.key) } }

    private let defaults = UserDefaults.standard
    private static let key = "strmrtv.showClock"

    private init() {
        enabled = defaults.object(forKey: Self.key) as? Bool ?? true
    }
}

/// The time as the device's settings write it ("9:41 PM", "21:41").
enum ClockFormat {
    static func string(_ date: Date = .now) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

/// Home's clock: the time on a glass pill like the top tab bar's, updated on each minute.
/// Not focusable and hit-testing off, so it never takes focus or presses.
struct ClockView: View {
    @ObservedObject private var settings = ClockSettingsStore.shared
    /// From the top of the screen, so the time sits level with the top tab bar's labels.
    static let top: CGFloat = 62 - PlayerClock.padV

    var body: some View {
        if settings.enabled {
            TimelineView(.everyMinute) { context in
                Text(ClockFormat.string(context.date))
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, PlayerClock.padH)
                    .padding(.vertical, PlayerClock.padV)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Where the player's clock sits: the top of the title-safe area, its trailing edge on the
/// transport bar's.
enum PlayerClock {
    static let top: CGFloat = 60 - padV
    static let trailing: CGFloat = 80
    /// The pill's padding around the time (Home and player alike).
    static let padH: CGFloat = 22
    static let padV: CGFloat = 8
}

/// The player's clock: a label on a dark glass-like pill that keeps itself current on minute
/// boundaries while it is in a window. Its owner fades it with the chrome it sits in.
final class PlayerClockLabel: UILabel {
    private var timer: Timer?

    init() {
        super.init(frame: .zero)
        font = .monospacedDigitSystemFont(ofSize: 30, weight: .semibold)
        textColor = UIColor.white.withAlphaComponent(0.9)
        textAlignment = .center
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        layer.masksToBounds = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        refresh()
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 2 * PlayerClock.padH, height: size.height + 2 * PlayerClock.padV)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Off in Settings: the label stays hidden whatever its owner does with its alpha.
    var clockEnabled: Bool {
        #if os(tvOS)
        ClockSettingsStore.shared.enabled
        #else
        false
        #endif
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        timer?.invalidate()
        timer = nil
        isHidden = !clockEnabled
        guard window != nil else { return }
        refresh()
        schedule()
    }

    /// Fires just after the next minute starts, then reschedules itself, so it never drifts.
    private func schedule() {
        let now = Date()
        let next = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0),
                                             matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
        let timer = Timer(fire: next.addingTimeInterval(0.05), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.schedule()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        text = ClockFormat.string()
        isHidden = !clockEnabled
    }
}
