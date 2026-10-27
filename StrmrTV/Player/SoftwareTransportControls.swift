import UIKit

/// The software route's stand-ins for AVKit's transport-bar buttons: round glass buttons that
/// open the same menus (`TransportMenuButton`), the Skip Intro / Next Episode capsule
/// (`TransportActionButton`) and the Info tab's card (`TransportInfoCard`). Measured against
/// AVKit's tvOS 26 chrome: 70 pt circles, 24 pt apart, white with a dark glyph when focused.
class TransportGlassButton: UIButton {
    /// Whether the button may take focus now (the row only after Up from the bar, as AVKit's).
    var focusable: () -> Bool = { true }

    init() {
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.25, alpha: 0.55)
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.borderWidth = 1
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 8)
        tintColor = .white
        setTitleColor(.white, for: .normal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var canBecomeFocused: Bool { focusable() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        let focused = isFocused
        coordinator.addCoordinatedAnimations {
            self.backgroundColor = focused ? .white : UIColor(white: 0.25, alpha: 0.55)
            self.tintColor = focused ? .black : .white
            self.setTitleColor(focused ? .black : .white, for: .normal)
            self.layer.shadowOpacity = focused ? 0.4 : 0
            self.transform = focused ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        }
    }
}

/// One of AVKit's round transport buttons, opening `menu` (Audio, Subtitles, Settings).
final class TransportMenuButton: TransportGlassButton {
    static let size: CGFloat = 70

    init(menu: UIMenu) {
        super.init()
        showsMenuAsPrimaryAction = true
        setMenu(menu)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size),
            heightAnchor.constraint(equalToConstant: Self.size),
        ])
    }

    func setMenu(_ menu: UIMenu) {
        self.menu = menu
        accessibilityLabel = menu.title
        let symbol = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        setImage(menu.image?.withConfiguration(symbol), for: .normal)
    }
}

/// AVKit's contextual action (Skip Intro, Next Episode): a glass capsule above the row.
final class TransportActionButton: TransportGlassButton {
    private var current: UIAction?

    init(action: UIAction) {
        super.init()
        titleLabel?.font = .systemFont(ofSize: 29, weight: .semibold)
        setAction(action)
    }

    /// Swaps the action in place (the Next Episode countdown retitles it every second), so a
    /// focused button keeps its focus.
    func setAction(_ action: UIAction) {
        if let current { removeAction(current, for: .primaryActionTriggered) }
        current = action
        addAction(action, for: .primaryActionTriggered)
        setTitle(action.title, for: .normal)
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: CGSize {
        let label = titleLabel?.intrinsicContentSize ?? .zero
        return CGSize(width: label.width + 80, height: max(label.height + 36, 70))
    }
}

/// What AVKit's Info tab shows (still, title, subtitle, the stream's summary), as a glass card
/// above the bar; Down on the bar opens it.
final class TransportInfoCard: UIView {
    private let artwork = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsLabel = UILabel()

    init(title: String, subtitle: String?) {
        super.init(frame: .zero)
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.layer.cornerRadius = 28
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        addSubview(blur)

        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 12
        artwork.layer.cornerCurve = .continuous
        artwork.isHidden = true
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 38, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle?.isEmpty ?? true
        subtitleLabel.font = .systemFont(ofSize: 29, weight: .medium)
        subtitleLabel.textColor = .white.withAlphaComponent(0.75)
        detailsLabel.isHidden = true
        detailsLabel.font = .systemFont(ofSize: 25, weight: .medium)
        detailsLabel.textColor = .white.withAlphaComponent(0.55)

        let titles = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, detailsLabel])
        titles.axis = .vertical
        titles.spacing = 8
        titles.setCustomSpacing(16, after: subtitleLabel)
        let row = UIStackView(arrangedSubviews: [artwork, titles])
        row.spacing = 36
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -48),
            artwork.widthAnchor.constraint(equalToConstant: 320),
            artwork.heightAnchor.constraint(equalToConstant: 180),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setArtwork(_ image: UIImage) {
        artwork.image = image
        artwork.isHidden = false
    }

    func setDetails(_ text: String?) {
        detailsLabel.text = text
        detailsLabel.isHidden = text?.isEmpty ?? true
    }
}
