import Foundation
import CoreGraphics
import CoreText
import ImageIO

public enum PDFBuilder {
    /// Writes pages into a single PDF at their true physical size.
    /// When `ocr` is true, an invisible text layer is drawn over each page so
    /// the PDF becomes searchable and text can be selected/copied.
    /// `onPageProcessed` fires per page (useful for progress UI — OCR is slow).
    public static func write(
        pages: [ScannedPage],
        to url: URL,
        ocr: Bool,
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for page in pages {
            let dpi = CGFloat(max(page.dpi, 1))
            let widthPts = CGFloat(page.image.width) / dpi * 72.0
            let heightPts = CGFloat(page.image.height) / dpi * 72.0
            var mediaBox = CGRect(x: 0, y: 0, width: widthPts, height: heightPts)

            context.beginPage(mediaBox: &mediaBox)
            context.draw(jpegBacked(page.image), in: mediaBox)

            if ocr {
                let lines = OCREngine.recognize(page.image)
                drawInvisibleText(lines, in: context, pageSize: mediaBox.size)
            }

            context.endPage()
            onPageProcessed?(page.index)
        }
        context.closePDF()
    }

    /// PDF contexts embed images created from JPEG data as-is (DCTDecode),
    /// instead of the huge lossless streams they build for raw bitmaps.
    private static func jpegBacked(_ image: CGImage) -> CGImage {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            return image
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination),
              let provider = CGDataProvider(data: data as Data as CFData),
              let jpeg = CGImage(
                  jpegDataProviderSource: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            return image
        }
        return jpeg
    }

    private static func drawInvisibleText(
        _ lines: [RecognizedLine],
        in context: CGContext,
        pageSize: CGSize
    ) {
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity

        for line in lines {
            let rect = CGRect(
                x: line.boundingBox.minX * pageSize.width,
                y: line.boundingBox.minY * pageSize.height,
                width: line.boundingBox.width * pageSize.width,
                height: line.boundingBox.height * pageSize.height
            )
            guard rect.width > 0.5, rect.height > 0.5 else { continue }

            // Scale the font so the drawn line matches the recognized box width,
            // keeping the searchable layer aligned with the printed words.
            let probeSize: CGFloat = 12
            let probeFont = CTFontCreateWithName("Helvetica" as CFString, probeSize, nil)
            let probeString = NSAttributedString(
                string: line.text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): probeFont]
            )
            let probeLine = CTLineCreateWithAttributedString(probeString)
            let probeWidth = CGFloat(CTLineGetTypographicBounds(probeLine, nil, nil, nil))
            guard probeWidth > 0 else { continue }

            let fontSize = min(probeSize * rect.width / probeWidth, rect.height * 1.2)
            let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
            let drawString = NSAttributedString(
                string: line.text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let ctLine = CTLineCreateWithAttributedString(drawString)
            let descent = CTFontGetDescent(font)

            context.textPosition = CGPoint(x: rect.minX, y: rect.minY + descent * 0.5)
            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
    }
}
