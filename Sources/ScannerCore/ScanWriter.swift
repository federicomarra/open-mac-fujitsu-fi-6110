import Foundation
import CoreGraphics
import ImageIO

public enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case searchablePDF
    case jpeg
    case png
    case tiff

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .pdf, .searchablePDF: return "pdf"
        case .jpeg: return "jpeg"
        case .png: return "png"
        case .tiff: return "tiff"
        }
    }

    var imageUTI: CFString? {
        switch self {
        case .jpeg: return "public.jpeg" as CFString
        case .png: return "public.png" as CFString
        case .tiff: return "public.tiff" as CFString
        case .pdf, .searchablePDF: return nil
        }
    }
}

public enum ScanWriter {
    /// Writes the scanned pages to `directory` using `baseName`.
    /// When `overwrite` is false (the default) an existing file is never
    /// clobbered — a `-1`, `-2`, … suffix is appended to find a free name.
    /// When `overwrite` is true the file at `baseName` is replaced.
    /// PDF formats produce one file; image formats produce one file per page.
    /// Returns the URLs written. `onPageProcessed` reports OCR/write progress.
    public static func write(
        pages: [ScannedPage],
        format: OutputFormat,
        directory: URL,
        baseName: String,
        overwrite: Bool = false,
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws -> [URL] {
        guard !pages.isEmpty else { return [] }
        let cleanBase = sanitized(baseName)

        switch format {
        case .pdf, .searchablePDF:
            let url = availableURL(directory: directory, base: cleanBase, ext: "pdf", overwrite: overwrite)
            try PDFBuilder.write(
                pages: pages,
                to: url,
                ocr: format == .searchablePDF,
                onPageProcessed: onPageProcessed
            )
            return [url]

        case .jpeg, .png, .tiff:
            var written: [URL] = []
            for page in pages {
                let base = pages.count == 1 ? cleanBase : "\(cleanBase) \(page.index)"
                let url = availableURL(directory: directory, base: base, ext: format.fileExtension, overwrite: overwrite)
                try writeImage(page, format: format, to: url)
                written.append(url)
                onPageProcessed?(page.index)
            }
            return written
        }
    }

    /// Re-writes `pages` to already-known URLs (from a previous `write`),
    /// overwriting them in place — no collision/suffix logic. Used when the user
    /// reorders the pages after scanning: the batch's own file(s) are updated,
    /// never spawning new suffixed copies nor touching unrelated files.
    /// PDF formats use `urls.first`; image formats map page *i* → `urls[i]`.
    public static func rewrite(
        pages: [ScannedPage],
        format: OutputFormat,
        to urls: [URL],
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws {
        guard !pages.isEmpty, !urls.isEmpty else { return }

        switch format {
        case .pdf, .searchablePDF:
            try PDFBuilder.write(
                pages: pages,
                to: urls[0],
                ocr: format == .searchablePDF,
                onPageProcessed: onPageProcessed
            )

        case .jpeg, .png, .tiff:
            for (offset, page) in pages.enumerated() where offset < urls.count {
                try writeImage(page, format: format, to: urls[offset])
                onPageProcessed?(offset + 1)
            }
        }
    }

    /// Writes a document that mixes pages from a PDF the user picked with
    /// freshly scanned ones ("add to a PDF"). Always a single PDF — importing is
    /// offered only while the format is PDF. Naming follows the same rules as
    /// `write`: `overwrite` replaces the file, otherwise "-1", "-2", … is added.
    /// Returns the URL written.
    public static func writeMerged(
        pages: [MergePage],
        searchable: Bool,
        directory: URL,
        baseName: String,
        overwrite: Bool = false,
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws -> URL {
        let url = availableURL(
            directory: directory,
            base: sanitized(baseName),
            ext: "pdf",
            overwrite: overwrite
        )
        try PDFMerger.write(pages: pages, to: url, ocr: searchable, onPageProcessed: onPageProcessed)
        return url
    }

    /// Re-writes a merged document to the file it already produced (after the
    /// user reorders or rotates its pages), overwriting it in place — the
    /// `rewrite` counterpart for the "add to a PDF" case.
    public static func rewriteMerged(
        pages: [MergePage],
        searchable: Bool,
        to url: URL,
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws {
        try PDFMerger.write(pages: pages, to: url, ocr: searchable, onPageProcessed: onPageProcessed)
    }

    private static func writeImage(_ page: ScannedPage, format: OutputFormat, to url: URL) throws {
        guard let uti = format.imageUTI,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, uti, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: page.dpi,
            kCGImagePropertyDPIHeight: page.dpi,
        ]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.85
        }
        CGImageDestinationAddImage(destination, page.image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    /// URL to write for `base`.`ext`. With `overwrite` the plain name is returned
    /// (replacing any existing file); otherwise the first free name is found by
    /// appending "-1", "-2", … : "Name.ext", then "Name-1.ext", "Name-2.ext"…
    private static func availableURL(directory: URL, base: String, ext: String, overwrite: Bool) -> URL {
        let plain = directory.appendingPathComponent("\(base).\(ext)")
        guard !overwrite else { return plain }
        let fm = FileManager.default
        var candidate = plain
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    private static func sanitized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "Scan" : cleaned
    }
}
