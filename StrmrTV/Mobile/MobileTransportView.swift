#if os(iOS)
import AVKit
import UIKit

/// The software route's touch transport, laid out as AVKit's iOS chrome: close, title and AirPlay
/// along the top; skip back, play / pause and skip forward in the middle; the scrubber with the
/// elapsed and remaining time along the bottom, and the seek preview above it while scrubbing.
final class MobileTransportView: UIView {
    var onClose: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?
    var onScrub: ((_ time: Double, _ ended: Bool) -> Void)?

    /// The scrubber's frame; the menu row sits above its trailing end.
    let barGuide = UILayoutGuide()
    /// The scrubber and its labels (touches inside go to the slider).
    let bar = UIView()
    private let topScrim = CAGradientLayer()
    private let bottomScrim = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsLabel = UILabel()
    /// A status capsule beside AirPlay ("● REC" on a growing recording); hidden without one.
    private let badge = TransportBadgeLabel()
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()
    private let playButton = UIButton()
    private let preview = ScrubPreviewView(imageSize: CGSize(width: 192, height: 108), compact: true)
    private var duration: Double = 0
    private(set) var isScrubbing = false
    static let skipStep: Double = 10

    init() {
        super.init(frame: .zero)
        for scrim in [topScrim, bottomScrim] {
            scrim.colors = [UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor]
            layer.addSublayer(scrim)
        }
        bottomScrim.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.7).cgColor]

        let close = Self.roundButton("xmark", label: String(localized: "Close"), size: 44) { [weak self] in self?.onClose?() }
        close.accessibilityIdentifier = "player.close"
        let airPlay = AVRoutePickerView()
        airPlay.tintColor = .white
        airPlay.activeTintColor = .systemBlue
        airPlay.prioritizesVideoDevices = true

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        detailsLabel.font = .preferredFont(forTextStyle: .caption1)
        detailsLabel.adjustsFontForContentSizeCategory = true
        for label in [titleLabel, subtitleLabel, detailsLabel] {
            label.textColor = .white
            label.lineBreakMode = .byTruncatingTail
        }
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        detailsLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        badge.isHidden = true
        let trailing = UIStackView(arrangedSubviews: [badge, airPlay])
        trailing.spacing = 10
        trailing.alignment = .center
        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titles.axis = .vertical
        titles.spacing = 2

        let back = Self.roundButton("gobackward.10", label: String(localized: "Back 10 seconds"), size: 60) { [weak self] in
            self?.onSkip?(-Self.skipStep)
        }
        let forward = Self.roundButton("goforward.10", label: String(localized: "Forward 10 seconds"), size: 60) { [weak self] in
            self?.onSkip?(Self.skipStep)
        }
        playButton.configuration = Self.roundConfiguration("pause.fill", pointSize: 32)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playButton.widthAnchor.constraint(equalToConstant: 80),
            playButton.heightAnchor.constraint(equalToConstant: 80),
        ])
        playButton.accessibilityLabel = String(localized: "Pause")
        playButton.accessibilityIdentifier = "player.playPause"
        playButton.addAction(UIAction { [weak self] _ in self?.onPlayPause?() }, for: .primaryActionTriggered)
        let center = UIStackView(arrangedSubviews: [back, playButton, forward])
        center.spacing = 36
        center.alignment = .center

        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.setThumbImage(Self.thumb(diameter: 14), for: .normal)
        slider.setThumbImage(Self.thumb(diameter: 22), for: .highlighted)
        slider.accessibilityIdentifier = "player.scrubber"
        slider.addTarget(self, action: #selector(scrubBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubMoved), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                                                    weight: .medium)
            label.textColor = .white
        }
        remainingLabel.textAlignment = .right
        preview.alpha = 0

        addLayoutGuide(barGuide)
        for view in [close, titles, trailing, center, bar, detailsLabel, preview] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for view in [slider, elapsedLabel, remainingLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(view)
        }
        let guide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            close.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            titles.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 14),
            titles.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            titles.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -14),
            trailing.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            trailing.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            airPlay.widthAnchor.constraint(equalToConstant: 44),
            airPlay.heightAnchor.constraint(equalToConstant: 44),

            center.centerXAnchor.constraint(equalTo: centerXAnchor),
            center.centerYAnchor.constraint(equalTo: centerYAnchor),

            bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            bar.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8),
            slider.topAnchor.constraint(equalTo: bar.topAnchor),
            slider.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            elapsedLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 2),
            elapsedLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            elapsedLabel.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            remainingLabel.firstBaselineAnchor.constraint(equalTo: elapsedLabel.firstBaselineAnchor),
            remainingLabel.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            barGuide.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            barGuide.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            barGuide.topAnchor.constraint(equalTo: bar.topAnchor),
            barGuide.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            detailsLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            detailsLabel.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -16),
            detailsLabel.trailingAnchor.constraint(lessThanOrEqualTo: centerXAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        topScrim.frame = CGRect(x: 0, y: 0, width: bounds.width, height: min(140, bounds.height / 3))
        let bottomHeight = min(200, bounds.height / 2.5)
        bottomScrim.frame = CGRect(x: 0, y: bounds.height - bottomHeight, width: bounds.width, height: bottomHeight)
        layoutPreview()
    }

    func setTitle(_ title: String, subtitle: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
    }

    func setDetails(_ text: String?) { detailsLabel.text = text }

    func setBadge(_ text: String?) {
        badge.text = text
        badge.isHidden = text == nil
    }

    func update(position: Double, duration: Double, paused: Bool) {
        self.duration = duration
        if !isScrubbing {
            slider.maximumValue = Float(max(duration, 1))
            slider.value = Float(position)
            setClock(position)
        }
        let symbol = paused ? "play.fill" : "pause.fill"
        if playButton.configuration?.image != UIImage(systemName: symbol) {
            playButton.configuration = Self.roundConfiguration(symbol, pointSize: 32)
            playButton.accessibilityLabel = paused ? String(localized: "Play") : String(localized: "Pause")
        }
    }

    private func setClock(_ position: Double) {
        elapsedLabel.text = SoftwareTransportHUD.clock(position)
        remainingLabel.text = duration > 0 ? "-" + SoftwareTransportHUD.clock(max(0, duration - position)) : nil
    }

    // MARK: Scrubbing

    @objc private func scrubBegan() {
        isScrubbing = true
    }

    @objc private func scrubMoved() {
        isScrubbing = true
        let time = Double(slider.value)
        setClock(time)
        onScrub?(time, false)
    }

    @objc private func scrubEnded() {
        isScrubbing = false
        onScrub?(Double(slider.value), true)
    }

    /// The seek target's thumbnail (or just its time) above the scrubber's thumb.
    func showPreview(time: Double, image: UIImage?, hasThumbnails: Bool) {
        preview.set(time: SoftwareTransportHUD.clock(time), image: image, showsImage: hasThumbnails)
        setNeedsLayout()
        layoutIfNeeded()
        guard preview.alpha < 1 else { return }
        UIView.animate(withDuration: 0.15) { self.preview.alpha = 1 }
    }

    func updatePreviewImage(_ image: UIImage) { preview.setImage(image) }

    func hidePreview() {
        guard preview.alpha > 0 else { return }
        UIView.animate(withDuration: 0.25) { self.preview.alpha = 0 }
    }

    private func layoutPreview() {
        let size = preview.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let track = slider.convert(slider.trackRect(forBounds: slider.bounds), to: self)
        guard track.width > 0 else { return }
        let fraction = duration > 0 ? CGFloat(Double(slider.value) / duration) : 0
        let centerX = track.minX + track.width * min(max(fraction, 0), 1)
        let x = min(max(centerX - size.width / 2, track.minX), track.maxX - size.width)
        preview.frame = CGRect(x: x, y: track.minY - 16 - size.height, width: size.width, height: size.height)
    }

    // MARK: Buttons

    /// A round glass button with an SF Symbol, as AVKit's.
    private static func roundConfiguration(_ symbol: String, pointSize: CGFloat) -> UIButton.Configuration {
        var config = MobilePlayerControls.glassConfiguration()
        config.image = UIImage(systemName: symbol)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        return config
    }

    private static func roundButton(_ symbol: String, label: String, size: CGFloat,
                                    action: @escaping () -> Void) -> UIButton {
        let config = roundConfiguration(symbol, pointSize: size > 44 ? 24 : 17)
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.accessibilityLabel = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])
        return button
    }

    private static func thumb(diameter: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { context in
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        }
    }
}
/// A small red capsule, as the system's live / recording indicators.
private final class TransportBadgeLabel: UILabel {
    private static let padding = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .bold))
        adjustsFontForContentSizeCategory = true
        textColor = .white
        backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        layer.cornerCurve = .continuous
        clipsToBounds = true
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + Self.padding.left + Self.padding.right,
                      height: size.height + Self.padding.top + Self.padding.bottom)
    }

    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: Self.padding)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
#endif
