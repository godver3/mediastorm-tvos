import UIKit

/// Thumbnail + time card shown above the software HUD's progress bar while seeking.
final class ScrubPreviewView: UIView {
    static let imageSize = CGSize(width: 384, height: 216)

    private let imageView = UIImageView()
    private let timeLabel = UILabel()

    override convenience init(frame: CGRect) {
        self.init(imageSize: Self.imageSize, compact: false)
    }

    /// `compact`: the phone's smaller card (smaller corners, time and shadow).
    init(imageSize: CGSize, compact: Bool) {
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = compact ? 8 : 12
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        imageView.layer.borderWidth = 1
        timeLabel.font = .monospacedDigitSystemFont(ofSize: compact ? 15 : 28, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.textAlignment = .center
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = compact ? 8 : 16
        layer.shadowOffset = CGSize(width: 0, height: compact ? 3 : 6)

        let stack = UIStackView(arrangedSubviews: [imageView, timeLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = compact ? 6 : 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: imageSize.height),
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
