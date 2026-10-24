import UIKit

/// Minimal transport readout for AetherEngine's software route (AV1/VP9/etc.), where
/// AVKit has no AVPlayer and therefore no transport bar of its own.
final class SoftwareTransportHUD: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    /// The stream's summary ("4K HEVC · HDR10 · E-AC-3 5.1 · Usenet"): the route has no Info tabs.
    private let detailsLabel = UILabel()
    /// The Info panel's still (episode still or backdrop), beside the title once loaded.
    private let artwork = UIImageView()
    private let timeLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let stateIcon = UIImageView()
    private let row: UIStackView
    private let preview = ScrubPreviewView()
    private var previewFraction: CGFloat = 0
    private var hideWork: DispatchWorkItem?
    private var paused = false

    init(title: String, subtitle: String? = nil) {
        row = UIStackView()
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 0

        let gradient = CAGradientLayer()
        gradient.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.8).cgColor]
        gradient.locations = [0.6, 1]
        layer.addSublayer(gradient)

        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .white
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        subtitleLabel.font = .preferredFont(forTextStyle: .callout)
        subtitleLabel.textColor = .white.withAlphaComponent(0.75)
        detailsLabel.isHidden = true
        detailsLabel.font = .preferredFont(forTextStyle: .caption1)
        detailsLabel.textColor = .white.withAlphaComponent(0.6)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 10
        artwork.layer.cornerCurve = .continuous
        artwork.isHidden = true
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .medium)
        timeLabel.textColor = .white.withAlphaComponent(0.8)
        progress.progressTintColor = .white
        progress.trackTintColor = .white.withAlphaComponent(0.3)
        stateIcon.tintColor = .white
        stateIcon.contentMode = .scaleAspectFit

        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, detailsLabel])
        titles.axis = .vertical
        titles.spacing = 4
        [artwork, stateIcon, titles, UIView(), timeLabel].forEach(row.addArrangedSubview)
        row.spacing = 20
        row.setCustomSpacing(28, after: artwork)
        row.alignment = .center
        let stack = UIStackView(arrangedSubviews: [row, progress])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 90),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -90),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -70),
            stateIcon.widthAnchor.constraint(equalToConstant: 36),
            stateIcon.heightAnchor.constraint(equalToConstant: 36),
            artwork.widthAnchor.constraint(equalToConstant: 256),
            artwork.heightAnchor.constraint(equalToConstant: 144),
        ])
        preview.alpha = 0
        addSubview(preview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.first?.frame = bounds
        layoutPreview()
    }

    /// Shows the Info panel's still beside the title.
    func setArtwork(_ image: UIImage) {
        artwork.image = image
        artwork.isHidden = false
    }

    func setDetails(_ text: String?) {
        detailsLabel.text = text
        detailsLabel.isHidden = text?.isEmpty ?? true
    }

    // MARK: Scrub preview

    /// Shows the seek target's thumbnail (if any) above the progress bar at `time`.
    /// A nil image keeps the previous one until the next arrives; with no thumbnails at
    /// all only the target time is shown.
    func showPreview(time: Double, duration: Double, image: UIImage?, hasThumbnails: Bool) {
        guard duration > 0 else { return }
        previewFraction = CGFloat(min(max(time / duration, 0), 1))
        preview.set(time: formatTimestamp(time), image: image, showsImage: hasThumbnails)
        setNeedsLayout()
        layoutIfNeeded()
        if preview.alpha < 1 { UIView.animate(withDuration: 0.15) { self.preview.alpha = 1 } }
    }

    /// Updates the image for the preview already on screen (a late load).
    func updatePreviewImage(_ image: UIImage) {
        preview.setImage(image)
    }

    func hidePreview() {
        guard preview.alpha > 0 else { return }
        UIView.animate(withDuration: 0.25) { self.preview.alpha = 0 }
    }

    private func layoutPreview() {
        let size = preview.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let bar = progress.convert(progress.bounds, to: self)
        let rowTop = row.convert(row.bounds, to: self).minY
        guard bar.width > 0 else { return }
        let centerX = bar.minX + bar.width * previewFraction
        let x = min(max(centerX - size.width / 2, bar.minX), bar.maxX - size.width)
        preview.frame = CGRect(x: x, y: rowTop - 24 - size.height, width: size.width, height: size.height)
    }

    func update(position: Double, duration: Double, paused: Bool) {
        progress.progress = duration > 0 ? Float(position / duration) : 0
        timeLabel.text = duration > 0
            ? "\(formatTimestamp(position)) / \(formatTimestamp(duration))"
            : formatTimestamp(position)
        if paused != self.paused {
            self.paused = paused
            if paused { flash() }
        }
        stateIcon.image = UIImage(systemName: paused ? "pause.fill" : "play.fill")
    }

    /// Shows the HUD; it auto-hides after a few seconds unless playback is paused.
    func flash() {
        hideWork?.cancel()
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.paused else { return }
            UIView.animate(withDuration: 0.4) { self.alpha = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}

/// Thumbnail + time card shown above the software HUD's progress bar while seeking.
private final class ScrubPreviewView: UIView {
    static let imageSize = CGSize(width: 384, height: 216)

    private let imageView = UIImageView()
    private let timeLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        imageView.layer.borderWidth = 1
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        let stack = UIStackView(arrangedSubviews: [imageView, timeLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Self.imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: Self.imageSize.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func set(time: String, image: UIImage?, showsImage: Bool) {
        timeLabel.text = time
        imageView.isHidden = !showsImage
        if let image { imageView.image = image }
    }

    func setImage(_ image: UIImage) {
        imageView.image = image
    }
}
