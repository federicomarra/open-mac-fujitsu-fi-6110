import CoreGraphics
import Foundation
import Vision

/// Detects a page fed upside-down and returns it the right way up (180° only).
///
/// Apple Vision recognizes text in any orientation, so the *content* it reads
/// can't tell upright from upside-down. The **geometry** can, though: Vision
/// reports character boxes in image space, so on a page fed upside-down every
/// word's characters run right-to-left. Counting the reading direction across
/// the page is a clean, reliable signal (one OCR pass, no trial rotations).
///
/// Pages with too little text (photos, near-blank sheets) are left untouched.
/// For duplex sheets the two sides share one physical orientation, so their
/// votes are combined and both faces flip (or stay) together — see `uprightPair`.
public enum OrientationCorrector {
    /// Minimum words with a clear reading direction before we trust the call.
    private static let minWords = 8

    /// Single page: flip when its text reads mostly right-to-left (upside-down).
    /// Blocking (runs Vision) — call on a background queue.
    public static func uprightImage(_ image: CGImage) -> CGImage {
        let v = votes(image)
        guard shouldFlip(leftToRight: v.leftToRight, rightToLeft: v.rightToLeft) else { return image }
        return rotated180(image) ?? image
    }

    /// Duplex sheet: both sides share one physical orientation, so the reading-
    /// direction votes of the two faces are summed and both flip (or stay)
    /// together. A blank back casts no votes and simply follows the side with text.
    public static func uprightPair(_ front: CGImage, _ back: CGImage) -> (CGImage, CGImage) {
        let f = votes(front)
        let b = votes(back)
        guard shouldFlip(
            leftToRight: f.leftToRight + b.leftToRight,
            rightToLeft: f.rightToLeft + b.rightToLeft
        ) else { return (front, back) }
        return (rotated180(front) ?? front, rotated180(back) ?? back)
    }

    // MARK: - Internals

    private static func shouldFlip(leftToRight: Int, rightToLeft: Int) -> Bool {
        guard leftToRight + rightToLeft >= minWords else { return false }
        return rightToLeft > leftToRight
    }

    /// Counts recognized words whose characters run left-to-right (upright) vs
    /// right-to-left (upside-down), from the geometry of the character boxes.
    private static func votes(_ image: CGImage) -> (leftToRight: Int, rightToLeft: Int) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["it-IT", "en-US"]
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else {
            return (0, 0)
        }

        var leftToRight = 0
        var rightToLeft = 0
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            guard text.count >= 4 else { continue }
            let firstRange = text.startIndex..<text.index(after: text.startIndex)
            let lastRange = text.index(before: text.endIndex)..<text.endIndex
            guard let firstBox = (try? candidate.boundingBox(for: firstRange)) ?? nil,
                  let lastBox = (try? candidate.boundingBox(for: lastRange)) ?? nil else { continue }
            if lastBox.boundingBox.midX > firstBox.boundingBox.midX {
                leftToRight += 1
            } else {
                rightToLeft += 1
            }
        }
        return (leftToRight, rightToLeft)
    }

    /// 180° rotation, preserving grayscale vs. color so B/W scans stay small.
    private static func rotated180(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let isGray = (image.colorSpace?.numberOfComponents ?? 3) == 1
        let colorSpace = isGray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = isGray
            ? CGImageAlphaInfo.none.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        context.translateBy(x: CGFloat(width), y: CGFloat(height))
        context.rotate(by: .pi)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
