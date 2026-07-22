import Foundation
import CoreGraphics
import Vision

/// One recognized line of text with its normalized bounding box
/// (Vision coordinates: origin bottom-left, 0…1 in both axes).
public struct RecognizedLine: Sendable {
    public let text: String
    public let boundingBox: CGRect
}

public enum OCREngine {
    /// Recognizes text in Italian + English (falling back to whatever the OS
    /// supports). Blocking — call from a background queue.
    public static func recognize(_ image: CGImage) -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let preferred = ["it-IT", "en-US"]
        if let supported = try? request.supportedRecognitionLanguages() {
            let matches = preferred.filter { code in
                supported.contains { $0.hasPrefix(String(code.prefix(2))) }
            }
            request.recognitionLanguages = matches.isEmpty ? supported : matches
        } else {
            request.recognitionLanguages = preferred
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.isEmpty else { return nil }
            return RecognizedLine(text: candidate.string, boundingBox: observation.boundingBox)
        }
    }
}
