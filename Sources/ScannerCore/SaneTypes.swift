import Foundation
import CoreGraphics

public enum ScanColorMode: String, CaseIterable, Identifiable, Sendable {
    case color = "Color"
    case gray = "Gray"
    case blackAndWhite = "Lineart"
    public var id: String { rawValue }
}

public enum PaperSize: String, CaseIterable, Identifiable, Sendable {
    case a4, a5, letter, legal
    public var id: String { rawValue }

    /// Physical size in millimeters.
    public var mm: (width: Double, height: Double) {
        switch self {
        case .a4: return (210.0, 297.0)
        case .a5: return (148.0, 210.0)
        case .letter: return (215.9, 279.4)
        case .legal: return (215.9, 355.6)
        }
    }
}

public struct ScanSettings: Sendable {
    public var mode: ScanColorMode = .color
    public var resolution: Int = 300
    public var duplex: Bool = false
    public var paperSize: PaperSize = .a4
    public var deskew: Bool = false
    public var skipBlankPages: Bool = false
    public init() {}
}

public struct ScannedPage: @unchecked Sendable {
    public let image: CGImage
    public let dpi: Int
    /// 1-based page number within the batch.
    public let index: Int
    public init(image: CGImage, dpi: Int, index: Int) {
        self.image = image
        self.dpi = dpi
        self.index = index
    }
}

public struct ScannerInfo: Equatable, Sendable {
    public let name: String   // SANE device name, e.g. "fujitsu:fi-6110dj:517446"
    public let vendor: String
    public let model: String
}

public enum ScanError: Error {
    /// A SANE call failed. `status` is the raw sane_strstatus text,
    /// `code` the numeric SANE_Status for mapping to friendly messages.
    case saneFailure(operation: String, status: String, code: Int32)
    case noScanner
    case cancelled
    case imageDecodeFailed

    public var isFeederEmpty: Bool {
        if case .saneFailure(_, _, let code) = self { return code == 7 /* SANE_STATUS_NO_DOCS */ }
        return false
    }

    public var isPaperJam: Bool {
        if case .saneFailure(_, _, let code) = self { return code == 6 /* SANE_STATUS_JAMMED */ }
        return false
    }

    public var isCoverOpen: Bool {
        if case .saneFailure(_, _, let code) = self { return code == 8 /* SANE_STATUS_COVER_OPEN */ }
        return false
    }
}
