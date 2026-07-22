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
    /// Writes the scanned pages to `directory` using `baseName`, never
    /// overwriting existing files (appends " 2", " 3", … like Finder).
    /// PDF formats produce one file; image formats produce one file per page.
    /// Returns the URLs written. `onPageProcessed` reports OCR/write progress.
    public static func write(
        pages: [ScannedPage],
        format: OutputFormat,
        directory: URL,
        baseName: String,
        onPageProcessed: ((Int) -> Void)? = nil
    ) throws -> [URL] {
        guard !pages.isEmpty else { return [] }
        let cleanBase = sanitized(baseName)

        switch format {
        case .pdf, .searchablePDF:
            let url = availableURL(directory: directory, base: cleanBase, ext: "pdf")
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
                let url = availableURL(directory: directory, base: base, ext: format.fileExtension)
                try writeImage(page, format: format, to: url)
                written.append(url)
                onPageProcessed?(page.index)
            }
            return written
        }
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

    /// First free URL for base name: "Name.ext", then "Name 2.ext", "Name 3.ext"…
    private static func availableURL(directory: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter).\(ext)")
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
