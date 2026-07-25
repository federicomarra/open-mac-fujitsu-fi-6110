import AppKit
import Foundation
import PDFKit
import ScannerCore
import SwiftUI
import UniformTypeIdentifiers

func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

struct PageItem: Identifiable {
    let id: Int
    /// Where this page comes from: the scanner, or the PDF the user picked.
    let source: MergePage
    let thumbnail: NSImage

    var isImported: Bool { source.isImported }
}

/// A PDF the user picked, with its pages' thumbnails already rendered off the
/// main thread. `@unchecked Sendable` so it can cross back to the main actor:
/// nothing else touches it until it is published.
private struct ImportedPDF: @unchecked Sendable {
    let document: PDFDocument
    let pages: [(page: PDFPage, thumbnail: NSImage)]
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
    /// Id of the page currently being dragged for reordering (nil when idle).
    @Published var draggingPageID: Int?

    // "Add to a PDF": the picked document, and the two confirmations it needs.
    @Published private(set) var importedPDFName: String?
    @Published private(set) var isImporting = false
    /// Scan pressed with pages already scanned onto a picked PDF.
    @Published var pendingAppendConfirm = false
    /// A PDF picked while pages are still on screen.
    @Published var pendingImportConfirm = false
    /// Id of the page waiting for the delete confirmation (nil when none is).
    @Published var deleteCandidateID: Int?

    // Scan settings (mirrors the options panel)
    @Published var mode: ScanColorMode = .color
    @Published var resolution: Int = 300
    @Published var paperSize: PaperSize = .a4
    @Published var duplex = false
    @Published var autoRotate = false
    @Published var deskew = true
    @Published var skipBlankPages = false
    @Published var overwrite = false
    @Published var format: OutputFormat = .pdf
    @Published var saveFolder: URL
    @Published var fileName: String

    let availableResolutions = [150, 200, 300, 400, 600]

    private let scanner: SaneScanner
    private let workQueue = DispatchQueue(label: "it.fi6110.scanner.work", qos: .userInitiated)
    private var pollTimer: Timer?
    private var probeInFlight = false
    /// Set while a drag actually moves pages, so the re-save fires only on real changes.
    private var reorderDidChange = false
    /// The picked PDF, held in memory so the merged result can be written back
    /// over that very file.
    private var importedDocument: PDFDocument?
    /// Page ids must stay unique across appended batches — `ScannedPage.index`
    /// restarts at 1 for every scan.
    private var nextPageID = 1
    /// Output settings as they were before a PDF was picked, so Clear can put
    /// them back (picking a PDF points them at that file).
    private var preImport: (folder: URL, name: String, overwrite: Bool)?

    init() {
        scanner = Self.makeScanner()
        // Seed the current selections from the user's saved defaults (Settings).
        mode = AppDefaults.mode
        resolution = AppDefaults.resolution
        paperSize = AppDefaults.paperSize
        duplex = AppDefaults.duplex
        autoRotate = AppDefaults.autoRotate
        deskew = AppDefaults.deskew
        skipBlankPages = AppDefaults.skipBlank
        overwrite = AppDefaults.overwrite
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

    /// Pages can be dragged only when idle and there's more than one.
    var canReorder: Bool { activity == .idle && pageItems.count > 1 }

    /// The pages the two bulk buttons act on. With a PDF loaded that's only what
    /// came out of the scanner: the picked document is never touched in bulk
    /// (a single page can still be turned with a double-click / right-click).
    private var bulkTargetIndices: [Int] {
        guard hasImportedPDF else { return Array(pageItems.indices) }
        return pageItems.indices.filter { !pageItems[$0].isImported }
    }

    var canFlipInBulk: Bool { activity == .idle && !bulkTargetIndices.isEmpty }

    var canReverseInBulk: Bool { activity == .idle && bulkTargetIndices.count > 1 }

    /// True while the chosen format produces a PDF — the only case where pages
    /// can be added to an existing document.
    var formatIsPDF: Bool { format == .pdf || format == .searchablePDF }

    var hasImportedPDF: Bool { importedDocument != nil }

    var hasScannedPages: Bool { pageItems.contains { !$0.isImported } }

    var canImportPDF: Bool { activity == .idle && !isImporting && formatIsPDF }

    /// The Scan button. With a PDF loaded and sheets already scanned onto it,
    /// ask first (add at the end / redo the scan / cancel); otherwise scan away.
    func requestScan() {
        guard canScan else { return }
        if hasImportedPDF && hasScannedPages {
            pendingAppendConfirm = true
        } else {
            startScan(append: hasImportedPDF)
        }
    }

    /// "Sostituisci le pagine scansionate": keep the picked PDF, drop the sheets
    /// scanned before, and scan a new batch onto it.
    func rescanReplacingScannedPages() {
        guard canScan else { return }
        pageItems.removeAll { !$0.isImported }
        startScan(append: true)
    }

    /// `append` keeps the pages already on screen (a picked PDF, or an earlier
    /// batch) and adds the new sheets after them; otherwise the list starts
    /// empty, as a plain scan always has.
    func startScan(append: Bool = false) {
        guard canScan else { return }
        if !append { pageItems = [] }
        savedMessage = nil
        savedURLs = []
        errorMessage = nil
        activity = .scanning(page: 1, progress: 0)

        var settings = ScanSettings()
        settings.mode = mode
        settings.resolution = resolution
        settings.paperSize = paperSize
        settings.duplex = duplex
        settings.autoRotate = autoRotate
        settings.deskew = deskew
        settings.skipBlankPages = skipBlankPages
        let outputFormat = format
        let directory = saveFolder
        let baseName = fileName
        let shouldOverwrite = overwrite
        let finalSettings = settings
        // Snapshot taken here rather than read back from `pageItems` at the end:
        // the appends below hop to the main actor, so their order relative to
        // the save is not guaranteed.
        let existing = pageItems.map(\.source)

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
                    let thumbnail = Self.thumbnail(for: page.image)
                    Task { @MainActor in
                        self.appendScannedPage(page, thumbnail: thumbnail)
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
                self.performSave(
                    pages: existing + collected.map { MergePage.scanned($0) },
                    existingURLs: [],
                    format: outputFormat,
                    directory: directory,
                    baseName: baseName,
                    overwrite: shouldOverwrite
                )
            } catch {
                Task { @MainActor in
                    self.activity = .idle
                    self.errorMessage = Self.friendlyMessage(for: error)
                }
            }
        }
    }

    private func appendScannedPage(_ page: ScannedPage, thumbnail: NSImage) {
        pageItems.append(PageItem(id: nextPageID, source: .scanned(page), thumbnail: thumbnail))
        nextPageID += 1
    }

    func cancelScan() {
        scanner.cancelScan()
    }

    func clearPages() {
        pageItems = []
        savedMessage = nil
        savedURLs = []
        draggingPageID = nil
        reorderDidChange = false
        importedDocument = nil
        importedPDFName = nil
        restorePreImportSettings()
    }

    // MARK: - Adding to an existing PDF

    /// The "Add to a PDF…" control: ask first when pages are on screen, since
    /// loading a document replaces the list.
    func requestImportPDF() {
        guard canImportPDF else { return }
        if pageItems.isEmpty {
            importPDF()
        } else {
            pendingImportConfirm = true
        }
    }

    func importPDF() {
        guard canImportPDF else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.pdf]
        panel.directoryURL = saveFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        errorMessage = nil
        workQueue.async { [weak self] in
            guard let self = self else { return }
            let loaded = Self.loadPDF(at: url)
            Task { @MainActor in
                self.isImporting = false
                guard let loaded = loaded else {
                    self.errorMessage = L("error.pdfOpen")
                    return
                }
                self.apply(loaded, from: url)
            }
        }
    }

    /// The X next to the picked file: forget the document and its pages, put the
    /// output settings back, and keep any pages that were scanned.
    func removeImportedPDF() {
        guard activity == .idle, hasImportedPDF else { return }
        importedDocument = nil
        importedPDFName = nil
        withAnimation { pageItems.removeAll { $0.isImported } }
        restorePreImportSettings()
        savedURLs = []
        savedMessage = nil
    }

    private nonisolated static func loadPDF(at url: URL) -> ImportedPDF? {
        // Read the bytes up front: the document is then backed by memory rather
        // than the file, so writing the merged result over that same file is safe.
        guard let data = try? Data(contentsOf: url),
              let document = PDFDocument(data: data),
              !document.isLocked,
              document.pageCount > 0 else { return nil }
        var pages: [(page: PDFPage, thumbnail: NSImage)] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            pages.append((page, thumbnail(for: page)))
        }
        guard !pages.isEmpty else { return nil }
        return ImportedPDF(document: document, pages: pages)
    }

    private func apply(_ loaded: ImportedPDF, from url: URL) {
        // Remember what the panel showed, so Clear can put it back.
        if preImport == nil {
            preImport = (folder: saveFolder, name: fileName, overwrite: overwrite)
        }
        importedDocument = loaded.document
        importedPDFName = url.lastPathComponent
        pageItems = loaded.pages.map { entry in
            let item = PageItem(id: nextPageID, source: .imported(entry.page), thumbnail: entry.thumbnail)
            nextPageID += 1
            return item
        }
        // The merged document is written back to the PDF the user picked.
        saveFolder = url.deletingLastPathComponent()
        fileName = url.deletingPathExtension().lastPathComponent
        overwrite = true
        savedURLs = []
        savedMessage = nil
        draggingPageID = nil
        reorderDidChange = false
    }

    private func restorePreImportSettings() {
        guard let preImport = preImport else { return }
        saveFolder = preImport.folder
        fileName = preImport.name
        overwrite = preImport.overwrite
        self.preImport = nil
    }

    // MARK: - Reordering

    /// Live reorder while dragging: move the dragged page to just before `targetID`.
    func moveDragged(beforeID targetID: Int) {
        guard activity == .idle,
              let draggingPageID, draggingPageID != targetID,
              let from = pageItems.firstIndex(where: { $0.id == draggingPageID }),
              let to = pageItems.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation {
            pageItems.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        reorderDidChange = true
    }

    /// End of a drag gesture: clear drag state and re-save if the order changed.
    func endReorder() {
        draggingPageID = nil
        guard reorderDidChange else { return }
        reorderDidChange = false
        resaveInPlace()
    }

    /// Reverse the page order and re-save. With a PDF loaded only the scanned
    /// pages are reversed, and only among the slots they already occupy: the
    /// picked document's pages don't move at all, even if a scan was dragged
    /// into the middle of them.
    func reversePages() {
        guard canReverseInBulk else { return }
        let slots = bulkTargetIndices
        withAnimation {
            for (slot, item) in zip(slots, slots.map { pageItems[$0] }.reversed()) {
                pageItems[slot] = item
            }
        }
        resaveInPlace()
    }

    /// Flip pages 180° at once (turns each image, refreshes thumbnails), then
    /// re-save. With a PDF loaded only the scanned pages are flipped.
    func flipAllPages() {
        guard canFlipInBulk else { return }
        withAnimation {
            for index in bulkTargetIndices {
                pageItems[index] = Self.rotated(pageItems[index], .flip)
            }
        }
        resaveInPlace()
    }

    /// Rotate a single page (from a double-click or the right-click menu):
    /// turns the page, refreshes its thumbnail, and re-saves.
    func rotatePage(id: Int, _ rotation: PageRotation) {
        guard activity == .idle, let index = pageItems.firstIndex(where: { $0.id == id }) else { return }
        let item = Self.rotated(pageItems[index], rotation)
        withAnimation { pageItems[index] = item }
        resaveInPlace()
    }

    // MARK: - Deleting a page

    /// Right-click ▸ "Elimina pagina": ask first. There is no undo — the page
    /// would have to be scanned again — and the saved file is rewritten at once.
    /// Works on the picked PDF's pages too, as a deliberate per-page gesture.
    func requestDeletePage(id: Int) {
        guard activity == .idle, pageItems.contains(where: { $0.id == id }) else { return }
        deleteCandidateID = id
    }

    /// 1-based position of the page waiting for confirmation, for the dialog.
    var deleteCandidatePosition: Int {
        guard let deleteCandidateID,
              let index = pageItems.firstIndex(where: { $0.id == deleteCandidateID }) else { return 0 }
        return index + 1
    }

    func confirmDeletePage() {
        guard activity == .idle, let id = deleteCandidateID,
              let index = pageItems.firstIndex(where: { $0.id == id }) else {
            deleteCandidateID = nil
            return
        }
        deleteCandidateID = nil
        withAnimation { _ = pageItems.remove(at: index) }
        // Nothing left: back to the opening screen, exactly like Svuota. The
        // file already written stays on disk as it is.
        guard !pageItems.isEmpty else {
            clearPages()
            return
        }
        resaveInPlace()
    }

    func cancelDeletePage() {
        deleteCandidateID = nil
    }

    /// Turns one page, whichever kind it is. Scanned pages get their bitmap
    /// rotated; a page from the picked PDF only gets its `rotation` changed, so
    /// its text and vector content stay untouched.
    private nonisolated static func rotated(_ item: PageItem, _ rotation: PageRotation) -> PageItem {
        switch item.source {
        case .scanned(let page):
            let image = ImageRotator.rotate(page.image, rotation)
            let turned = ScannedPage(image: image, dpi: page.dpi, index: page.index)
            return PageItem(id: item.id, source: .scanned(turned), thumbnail: thumbnail(for: image))
        case .imported(let page):
            let delta: Int
            switch rotation {
            case .right: delta = 90
            case .left: delta = -90
            case .flip: delta = 180
            }
            page.rotation = normalizedRotation(page.rotation + delta)
            return PageItem(id: item.id, source: .imported(page), thumbnail: thumbnail(for: page))
        }
    }

    /// PDFKit wants a rotation of 0, 90, 180 or 270 degrees.
    private nonisolated static func normalizedRotation(_ degrees: Int) -> Int {
        let wrapped = degrees % 360
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Re-writes the current page order to the file this batch already saved,
    /// overwriting it in place (never spawning "-2"/"-3" copies). Does nothing
    /// until a file exists: rotating or reordering a document that has not been
    /// saved yet must not create one — with a PDF picked that would rewrite the
    /// user's original file. The next scan writes the order shown anyway.
    private func resaveInPlace() {
        guard activity == .idle, !pageItems.isEmpty, !savedURLs.isEmpty else { return }
        let pages = pageItems.map(\.source)
        let existingURLs = savedURLs
        let outputFormat = format
        let directory = saveFolder
        let baseName = fileName
        let shouldOverwrite = overwrite

        savedMessage = nil
        activity = .saving(page: 0, total: pages.count, ocr: outputFormat == .searchablePDF)

        workQueue.async { [weak self] in
            self?.performSave(
                pages: pages,
                existingURLs: existingURLs,
                format: outputFormat,
                directory: directory,
                baseName: baseName,
                overwrite: shouldOverwrite
            )
        }
    }

    /// Writes `pages` (already in the order shown on screen) and reports the
    /// result. Runs on `workQueue`. A non-empty `existingURLs` re-writes those
    /// files in place instead of picking a fresh name.
    private nonisolated func performSave(
        pages: [MergePage],
        existingURLs: [URL],
        format: OutputFormat,
        directory: URL,
        baseName: String,
        overwrite: Bool
    ) {
        let ocr = format == .searchablePDF
        // Only scanned pages are rendered, so they alone drive the progress bar.
        let total = pages.reduce(0) { $1.isImported ? $0 : $0 + 1 }
        let progress: (Int) -> Void = { page in
            Task { @MainActor in self.activity = .saving(page: page, total: total, ocr: ocr) }
        }

        do {
            let finalURLs: [URL]
            if pages.contains(where: { $0.isImported }) {
                // "Add to a PDF" — always a single PDF, since importing is
                // offered only while the format is PDF.
                if let existing = existingURLs.first {
                    try ScanWriter.rewriteMerged(
                        pages: pages, searchable: ocr, to: existing, onPageProcessed: progress
                    )
                    finalURLs = [existing]
                } else {
                    finalURLs = [try ScanWriter.writeMerged(
                        pages: pages,
                        searchable: ocr,
                        directory: directory,
                        baseName: baseName,
                        overwrite: overwrite,
                        onPageProcessed: progress
                    )]
                }
            } else {
                let scanned = pages.compactMap(\.scannedPage)
                if existingURLs.isEmpty {
                    finalURLs = try ScanWriter.write(
                        pages: scanned,
                        format: format,
                        directory: directory,
                        baseName: baseName,
                        overwrite: overwrite,
                        onPageProcessed: progress
                    )
                } else {
                    try ScanWriter.rewrite(
                        pages: scanned, format: format, to: existingURLs, onPageProcessed: progress
                    )
                    finalURLs = existingURLs
                }
            }
            Task { @MainActor in self.finishSave(urls: finalURLs) }
        } catch {
            Task { @MainActor in
                self.activity = .idle
                self.errorMessage = Self.friendlyMessage(for: error)
            }
        }
    }

    private func finishSave(urls: [URL]) {
        activity = .idle
        savedURLs = urls
        guard let first = urls.first else { return }
        let name = urls.count == 1
            ? first.lastPathComponent
            : String(format: L("msg.savedMultiple %d"), urls.count)
        savedMessage = String(format: L("msg.saved %@"), name)
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

    /// Thumbnail of a page from the picked PDF. PDFKit renders it honouring the
    /// page's rotation, and the box is measured the same way so turned pages
    /// keep the right shape.
    private nonisolated static func thumbnail(for page: PDFPage, maxDimension: CGFloat = 480) -> NSImage {
        let bounds = page.bounds(for: .cropBox)
        let quarterTurned = normalizedRotation(page.rotation) % 180 == 90
        let width = quarterTurned ? bounds.height : bounds.width
        let height = quarterTurned ? bounds.width : bounds.height
        let longest = max(width, height)
        guard longest > 0 else { return NSImage(size: NSSize(width: 1, height: 1)) }
        let scale = maxDimension / longest
        let size = NSSize(width: max(width * scale, 1), height: max(height * scale, 1))
        return page.thumbnail(of: size, for: .cropBox)
    }
}
