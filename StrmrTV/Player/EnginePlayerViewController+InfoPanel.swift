import AVKit
import UIKit

/// AVKit's Info tab (swipe down on the hardware route): title, subtitle, description and,
/// as the Apple TV app shows it, a 16:9 still beside them. The artwork is downloaded and
/// sized once per session; the software route's HUD shows the same image.
extension EnginePlayerViewController {
    /// The artwork's pixel size (16:9).
    static let infoArtworkSize = CGSize(width: 800, height: 450)

    /// Sets the info panel's text at once and adds `artworkURL`'s image when it has loaded.
    func setInfoPanel(title: String, subtitle: String?, description: String?, artworkURL: URL? = nil) {
        let items = Self.infoPanelItems(title: title, subtitle: subtitle, description: description)
        engine.setExternalMetadata(items)
        infoArtworkTask?.cancel()
        guard let artworkURL else { return }
        infoArtworkTask = Task { [weak self] in
            guard let image = await Self.infoArtwork(from: artworkURL), !Task.isCancelled,
                  let self, let artwork = Self.artworkItem(image) else { return }
            engine.setExternalMetadata(items + [artwork])
            infoArtworkDidLoad(image)
        }
    }

    /// The artwork arrived; the software route's HUD shows it too. Subclasses override it.
    @objc func infoArtworkDidLoad(_ image: UIImage) {}

    static func infoPanelItems(title: String, subtitle: String?, description: String?) -> [AVMetadataItem] {
        var items = [metadataItem(.commonIdentifierTitle, title as NSString)]
        if let subtitle, !subtitle.isEmpty {
            items.append(metadataItem(.iTunesMetadataTrackSubTitle, subtitle as NSString))
        }
        if let description, !description.isEmpty {
            items.append(metadataItem(.commonIdentifierDescription, description as NSString))
        }
        return items
    }

    /// The image as a JPEG artwork item, which AVKit's Info tab draws beside the text.
    static func artworkItem(_ image: UIImage) -> AVMetadataItem? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierArtwork
        item.value = data as NSData
        item.dataType = kCMMetadataBaseDataType_JPEG as String
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem
    }

    /// Downloads the image and draws it into a 16:9 frame: a landscape image (still,
    /// backdrop) fills it, a portrait one (a poster fallback) is fitted on black.
    static func infoArtwork(from url: URL) async -> UIImage? {
        let size = infoArtworkSize
        guard let source = await ImagePipeline.load(url, size: size, mode: .fill, scale: 1) else { return nil }
        let aspect = source.size.width / max(source.size.height, 1)
        let fills = aspect >= 1.3
        let scale = fills ? max(size.width / source.size.width, size.height / source.size.height)
                          : min(size.width / source.size.width, size.height / source.size.height)
        let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            source.draw(in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                                   width: drawn.width, height: drawn.height))
        }
    }

    private static func metadataItem(_ id: AVMetadataIdentifier, _ value: NSString) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = id
        item.value = value
        item.extendedLanguageTag = "und"
        return item.copy() as! AVMetadataItem
    }
}
