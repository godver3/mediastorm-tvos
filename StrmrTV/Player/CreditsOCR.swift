import CoreGraphics
import Vision

/// Reads the text lines in a still for credits detection: Vision's fast recogniser, no
/// language correction (names aren't words), small text allowed. Blocking; call off the main actor.
enum CreditsOCR {
    static func lines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
