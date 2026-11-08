#if os(iOS)
import AetherEngine
import UIKit

/// Phone / tablet geometry for `SubtitleOverlayView`. A TV's style is laid out on its 1920×1080
/// screen; here that screen is the largest 16:9 frame that fits the overlay (the whole height in
/// landscape, the video's band across the width in portrait), and the style is drawn at that
/// frame's height over 1080, so each size covers the same share of the picture as on a TV.
extension SubtitleOverlayView {
    /// The 16:9 frame a TV's 1920×1080 screen maps to, centred in `bounds`.
    static func canvas(in bounds: CGRect) -> CGRect { fit(16 / 9, in: bounds) }

    /// The `aspect` (width / height) rect that fits `bounds`, centred: where an aspect-fit picture is.
    static func fit(_ aspect: CGFloat, in bounds: CGRect) -> CGRect {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let width = min(bounds.width, bounds.height * aspect)
        let height = width / aspect
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    /// The rect a bitmap cue's normalized position maps onto: the picture (16:9 until the source's
    /// size is known), or the cue's canvas mapped width-aligned and centred on it when the canvas has
    /// a different shape (a cropped rip's 1920×1080 canvas over a 1920×804 picture), as the engine
    /// asks, so cues land where the disc put them.
    static func bitmapArea(for image: SubtitleImage, videoSize: CGSize, pixelAspect: CGFloat,
                           in bounds: CGRect) -> CGRect {
        let known = videoSize.width > 0 && videoSize.height > 0
        let picture = fit(known ? videoSize.width * max(pixelAspect, 0.01) / videoSize.height : 16 / 9, in: bounds)
        let canvas = image.canvasSize
        guard known, canvas.width > 0, canvas.height > 0 else { return picture }
        // The canvas spans the coded width, so it is canvas.h × coded.w / canvas.w coded rows tall.
        let height = picture.height * canvas.height * videoSize.width / (canvas.width * videoSize.height)
        return CGRect(x: picture.minX, y: picture.midY - height / 2, width: picture.width, height: height)
    }
}
#endif
