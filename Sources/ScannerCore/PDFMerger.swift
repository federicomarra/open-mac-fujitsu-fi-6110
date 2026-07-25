import Foundation
import PDFKit

/// One page of a document being assembled: either freshly scanned (an image
/// that still has to be rendered) or a page taken from a PDF the user picked.
public enum MergePage: @unchecked Sendable {
    case scanned(ScannedPage)
    case imported(PDFPage)

    public var isImported: Bool {
        if case .imported = self { return true }
        return false
    }

    public var scannedPage: ScannedPage? {
        if case .scanned(let page) = self { return page }
        return nil
    }
}

public enum PDFMerger {
    /// Writes `pages`, in the order given, as a single PDF at `url`.
    ///
    /// Pages coming from the picked document are copied through untouched, so
    /// its real text, vector drawings and modest file size survive. Scanned
    /// pages are rendered by `PDFBuilder` — JPEG-backed, plus the invisible OCR
    /// layer when `ocr` is true, which therefore never runs over imported pages.
    /// `onPageProcessed` reports the scanned pages as they are rendered (1-based).
    public static func write(
        pages: [MergePage],
        to url: URL,
        ocr: Bool,
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws {
        guard !pages.isEmpty else { return }

        // Render the scanned pages first, renumbered 1…n in the order they
        // appear on screen so progress stays sequential even after several
        // batches have been appended.
        var scanned: [ScannedPage] = []
        for page in pages {
            guard let scan = page.scannedPage else { continue }
            scanned.append(ScannedPage(image: scan.image, dpi: scan.dpi, index: scanned.count + 1))
        }

        let fileManager = FileManager.default
        var temporaryURL: URL?
        defer {
            if let temporaryURL { try? fileManager.removeItem(at: temporaryURL) }
        }

        var scannedDocument: PDFDocument?
        if !scanned.isEmpty {
            let temporary = fileManager.temporaryDirectory
                .appendingPathComponent("fi6110-merge-\(UUID().uuidString).pdf")
            temporaryURL = temporary
            try PDFBuilder.write(pages: scanned, to: temporary, ocr: ocr, onPageProcessed: onPageProcessed)
            guard let document = PDFDocument(url: temporary) else {
                throw CocoaError(.fileReadUnknown)
            }
            scannedDocument = document
        }

        let output = PDFDocument()
        var scannedCursor = 0
        for page in pages {
            let source: PDFPage?
            switch page {
            case .imported(let imported):
                source = imported.copy() as? PDFPage
            case .scanned:
                source = scannedDocument?.page(at: scannedCursor)?.copy() as? PDFPage
                scannedCursor += 1
            }
            guard let source else { continue }
            output.insert(source, at: output.pageCount)
        }

        guard output.pageCount > 0, output.write(to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
