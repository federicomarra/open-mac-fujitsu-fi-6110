import AppKit
import Foundation
import ScannerCore
import SwiftUI

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

struct PageItem: Identifiable {
    let id: Int
    let page: ScannedPage
    let thumbnail: NSImage
}

@MainActor
final class ScannerViewModel: ObservableObject {
    enum Status: Equatable {
        case searching
        case connected(model: String)
        case notFound
    }

    enum Activity: Equatable {
        case idle
        case scanning(page: Int, progress: Double)
        case saving(page: Int, total: Int, ocr: Bool)
    }

    @Published private(set) var status: Status = .searching
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var pageItems: [PageItem] = []
    @Published var errorMessage: String?
    @Published private(set) var savedMessage: String?
    @Published private(set) var savedURLs: [URL] = []

    // Scan settings (mirrors the options panel)
    @Published var mode: ScanColorMode = .color
    @Published var resolution: Int = 300
    @Published var paperSize: PaperSize = .a4
    @Published var duplex = false
    @Published var deskew = true
    @Published var skipBlankPages = false
    @Published var format: OutputFormat = .pdf
    @Published var saveFolder: URL
    @Published var fileName: String

    let availableResolutions = [150, 200, 300, 400, 600]

    private let scanner: SaneScanner
    private let workQueue = DispatchQueue(label: "it.fi6110.scanner.work", qos: .userInitiated)
    private var pollTimer: Timer?
    private var probeInFlight = false

    init() {
        scanner = Self.makeScanner()
        // Seed the current selections from the user's saved defaults (Settings).
        mode = AppDefaults.mode
        resolution = AppDefaults.resolution
        paperSize = AppDefaults.paperSize
        duplex = AppDefaults.duplex
        deskew = AppDefaults.deskew
        skipBlankPages = AppDefaults.skipBlank
        format = AppDefaults.format
        saveFolder = AppDefaults.saveFolder
        fileName = Self.defaultFileName()
        startPolling()
    }

    /// Default document name: today's date plus the localized "scan" word,
    /// e.g. "2026-07-23-scansione". POSIX locale keeps the digits stable.
    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: Date()))-\(L("name.suffix"))"
    }

    /// Display name of the save folder in the app's language (e.g. "Documenti"
    /// rather than the on-disk "Documents"). Standard folders use the app's own
    /// translations — the same ones the picker menu shows — because the system's
    /// folder localization does not reliably follow the app's language; custom
    /// folders fall back to their real name.
    var saveFolderDisplayName: String {
        let fm = FileManager.default
        func matches(_ directory: FileManager.SearchPathDirectory) -> Bool {
            guard let url = fm.urls(for: directory, in: .userDomainMask).first else { return false }
            return url.standardizedFileURL.path == saveFolder.standardizedFileURL.path
        }
        if matches(.documentDirectory) { return L("saveto.documents") }
        if matches(.desktopDirectory) { return L("saveto.desktop") }
        if matches(.downloadsDirectory) { return L("saveto.downloads") }
        let name = fm.displayName(atPath: saveFolder.path)
        return name.isEmpty ? saveFolder.lastPathComponent : name
    }

    /// In the packaged app the SANE module + config live inside the bundle;
    /// during `swift run` development they come from vendor/out.
    private static func makeScanner() -> SaneScanner {
        let bundle = Bundle.main
        if let frameworks = bundle.privateFrameworksURL,
           FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("libsane-fujitsu.so").path),
           let resources = bundle.resourceURL {
            return SaneScanner(
                libraryDir: frameworks,
                configDir: resources.appendingPathComponent("sane.d")
            )
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return SaneScanner(
            libraryDir: repo.appendingPathComponent("vendor/out/lib"),
            configDir: repo.appendingPathComponent("vendor/out/etc/sane.d")
        )
    }

    // MARK: - Device polling

    private func startPolling() {
        probeNow()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.probeNow() }
        }
    }

    private func probeNow() {
        guard activity == .idle, !probeInFlight else { return }
        probeInFlight = true
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let found = try? self.scanner.probeForScanner()
            Task { @MainActor in
                self.probeInFlight = false
                guard self.activity == .idle else { return }
                if let found = found ?? nil {
                    self.status = .connected(model: "\(found.vendor) \(found.model)")
                } else {
                    self.status = self.status == .searching ? .notFound : .notFound
                }
            }
        }
    }

    // MARK: - Scanning

    var canScan: Bool {
        if case .connected = status, activity == .idle { return true }
        return false
    }

    func startScan() {
        guard canScan else { return }
        pageItems = []
        savedMessage = nil
        savedURLs = []
        errorMessage = nil
        activity = .scanning(page: 1, progress: 0)

        var settings = ScanSettings()
        settings.mode = mode
        settings.resolution = resolution
        settings.paperSize = paperSize
        settings.duplex = duplex
        settings.deskew = deskew
        settings.skipBlankPages = skipBlankPages
        let outputFormat = format
        let directory = saveFolder
        let baseName = fileName
        let finalSettings = settings

        workQueue.async { [weak self] in
            guard let self = self else { return }
            var collected: [ScannedPage] = []
            do {
                let count = try self.scanner.scan(settings: finalSettings, onProgress: { page, fraction in
                    Task { @MainActor in
                        self.activity = .scanning(page: page, progress: fraction)
                    }
                }, onPage: { page in
                    collected.append(page)
                    let item = PageItem(
                        id: page.index,
                        page: page,
                        thumbnail: Self.thumbnail(for: page.image)
                    )
                    Task { @MainActor in
                        self.pageItems.append(item)
                        self.activity = .scanning(page: page.index + 1, progress: 0)
                    }
                })

                guard count > 0 else {
                    Task { @MainActor in
                        self.activity = .idle
                        self.errorMessage = L("msg.feederEmpty")
                    }
                    return
                }

                let ocr = outputFormat == .searchablePDF
                Task { @MainActor in
                    self.activity = .saving(page: 0, total: count, ocr: ocr)
                }
                let urls = try ScanWriter.write(
                    pages: collected,
                    format: outputFormat,
                    directory: directory,
                    baseName: baseName,
                    onPageProcessed: { page in
                        Task { @MainActor in
                            self.activity = .saving(page: page, total: count, ocr: ocr)
                        }
                    }
                )
                Task { @MainActor in
                    self.activity = .idle
                    self.savedURLs = urls
                    if let first = urls.first {
                        let name = urls.count == 1
                            ? first.lastPathComponent
                            : String(format: L("msg.savedMultiple %d"), urls.count)
                        self.savedMessage = String(format: L("msg.saved %@"), name)
                    }
                }
            } catch {
                Task { @MainActor in
                    self.activity = .idle
                    self.errorMessage = Self.friendlyMessage(for: error)
                }
            }
        }
    }

    func cancelScan() {
        scanner.cancelScan()
    }

    func clearPages() {
        pageItems = []
        savedMessage = nil
        savedURLs = []
    }

    func showSavedInFinder() {
        guard !savedURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(savedURLs)
    }

    func chooseSaveFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = saveFolder
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url
        }
    }

    // MARK: - Helpers

    private static func friendlyMessage(for error: Error) -> String? {
        guard let scanError = error as? ScanError else {
            return String(format: L("error.generic %@"), error.localizedDescription)
        }
        switch scanError {
        case .cancelled:
            return nil
        case .noScanner:
            return L("error.noScanner")
        case .imageDecodeFailed:
            return L("error.decode")
        case .saneFailure:
            if scanError.isPaperJam { return L("error.jam") }
            if scanError.isCoverOpen { return L("error.coverOpen") }
            if scanError.isFeederEmpty { return L("msg.feederEmpty") }
            if case .saneFailure(let op, let status, _) = scanError {
                return String(format: L("error.generic %@"), "\(op): \(status)")
            }
            return L("error.generic %@")
        }
    }

    private nonisolated static func thumbnail(for image: CGImage, maxDimension: CGFloat = 480) -> NSImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height))
        let size = NSSize(width: width * scale, height: height * scale)
        let nsImage = NSImage(cgImage: image, size: size)
        return nsImage
    }
}
