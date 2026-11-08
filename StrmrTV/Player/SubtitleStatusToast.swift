import UIKit

/// The online-subtitle status line ("Searching for subtitles…", "Subtitles ready") in the
/// player's top-right corner (a phone: a small capsule centred under the top controls), over both
/// routes' video and chrome. Passes touches and focus by.
final class SubtitleStatusToast: UIView {
    /// Sizes for the TV (10-foot, fixed) and the phone (the footnote text style, Dynamic Type).
    private struct Metrics {
        var cornerRadius: CGFloat
        var padding: CGSize
        var spacing: CGFloat
        var icon: CGFloat
    }

    #if os(iOS)
    private static let metrics = Metrics(cornerRadius: 16, padding: CGSize(width: 14, height: 8), spacing: 6, icon: 15)
    #else
    private static let metrics = Metrics(cornerRadius: 22, padding: CGSize(width: 26, height: 14), spacing: 14, icon: 30)
    #endif

    private let label = UILabel()
    private let icon = UIImageView(image: UIImage(systemName: "captions.bubble"))
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false

        let metrics = Self.metrics
        #if os(iOS)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        #else
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        #endif
        blur.layer.cornerRadius = metrics.cornerRadius
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        #if os(iOS)
        label.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        #else
        label.font = .systemFont(ofSize: 26, weight: .medium)
        #endif
        label.textColor = .white
        label.accessibilityIdentifier = "subtitleStatus"
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = metrics.spacing
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: metrics.padding.width),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -metrics.padding.width),
            row.topAnchor.constraint(equalTo: topAnchor, constant: metrics.padding.height),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -metrics.padding.height),
            icon.widthAnchor.constraint(equalToConstant: metrics.icon),
            icon.heightAnchor.constraint(equalToConstant: metrics.icon),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Pins the toast to `host`'s top-right corner; on a phone, centred below the top row of
    /// controls (close and title, AVKit's volume group, the Audio / Subtitles / Settings menus),
    /// clear of the middle play / skip buttons.
    func install(in host: UIView) {
        host.addSubview(self)
        #if os(iOS)
        let guide = host.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide.topAnchor, constant: 68),
            centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            widthAnchor.constraint(lessThanOrEqualTo: guide.widthAnchor, constant: -32),
        ])
        #else
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor, constant: 60),
            trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -80),
        ])
        #endif
    }

    /// Shows `text`; it fades out after `hideAfter` seconds, or stays until the next call.
    func show(_ text: String, hideAfter: TimeInterval?) {
        hideWork?.cancel()
        label.text = text
        superview?.bringSubviewToFront(self)
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        guard let hideAfter else { return }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        UIView.animate(withDuration: 0.4) { self.alpha = 0 }
    }
}
