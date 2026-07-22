import Foundation
import CSane

/// Blocking wrapper around the bundled SANE fujitsu backend.
/// All methods except `cancelScan()` must be called from a single background
/// thread/queue — SANE calls block for the duration of hardware operations.
/// @unchecked Sendable: thread discipline is enforced by the caller (single
/// work queue) and `cancelScan()` is protected by `stateLock`.
public final class SaneScanner: @unchecked Sendable {
    private let modulePath: String
    private var api: SaneAPI?
    private var initialized = false

    private let stateLock = NSLock()
    private var currentHandle: UnsafeMutableRawPointer?

    /// - Parameters:
    ///   - libraryDir: directory containing libsane-fujitsu.so (+ libusb next to it)
    ///   - configDir: directory containing fujitsu.conf
    public init(libraryDir: URL, configDir: URL) {
        modulePath = libraryDir.appendingPathComponent("libsane-fujitsu.so").path
        setenv("SANE_CONFIG_DIR", configDir.path, 1)
    }

    deinit {
        shutdown()
    }

    // MARK: - Lifecycle

    private func ensureAPI() throws -> SaneAPI {
        if let api = api { return api }
        let loaded = try SaneAPI(modulePath: modulePath)
        api = loaded
        return loaded
    }

    private func ensureInit(_ api: SaneAPI) throws {
        guard !initialized else { return }
        let status = api.saneInit(nil, nil)
        guard status == SANE_STATUS_GOOD else {
            throw failure(api, "sane_init", status)
        }
        initialized = true
    }

    /// Tear down the SANE session (usable again afterwards — it re-inits lazily).
    public func shutdown() {
        if initialized, let api = api {
            api.saneExit()
            initialized = false
        }
    }

    // MARK: - Discovery

    /// Fresh USB probe for the scanner. Cycles sane_exit/sane_init so hot-plugged
    /// devices are found. Blocking; only call while no scan is running.
    public func probeForScanner() throws -> ScannerInfo? {
        let api = try ensureAPI()
        shutdown()
        try ensureInit(api)
        return try firstDevice(api)
    }

    private func firstDevice(_ api: SaneAPI) throws -> ScannerInfo? {
        var list: UnsafeMutablePointer<UnsafePointer<SANE_Device>?>? = nil
        let status = api.getDevices(&list, 1 /* local only */)
        guard status == SANE_STATUS_GOOD else {
            throw failure(api, "sane_get_devices", status)
        }
        guard let list = list else { return nil }
        var i = 0
        while let device = list[i] {
            let d = device.pointee
            let info = ScannerInfo(
                name: d.name.map { String(cString: $0) } ?? "",
                vendor: d.vendor.map { String(cString: $0) } ?? "",
                model: d.model.map { String(cString: $0) } ?? ""
            )
            if !info.name.isEmpty { return info }
            i += 1
        }
        return nil
    }

    // MARK: - Scanning

    /// Runs a full ADF batch scan. Blocking — call from a background queue.
    /// `onPage` fires after each completed page; `onProgress` reports
    /// (pageNumber, fractionOfPage). Returns the number of pages scanned
    /// (0 means the feeder was empty).
    @discardableResult
    public func scan(
        settings: ScanSettings,
        onProgress: ((Int, Double) -> Void)? = nil,
        onPage: (ScannedPage) -> Void
    ) throws -> Int {
        let api = try ensureAPI()
        shutdown()  // fresh session so a re-plugged scanner is picked up
        try ensureInit(api)

        guard let info = try firstDevice(api) else { throw ScanError.noScanner }

        var handle: UnsafeMutableRawPointer? = nil
        let openStatus = info.name.withCString { api.open($0, &handle) }
        guard openStatus == SANE_STATUS_GOOD, let h = handle else {
            throw failure(api, "sane_open", openStatus)
        }
        stateLock.lock(); currentHandle = h; stateLock.unlock()
        defer {
            stateLock.lock(); currentHandle = nil; stateLock.unlock()
            api.close(h)
        }

        try configure(h, api: api, settings: settings)

        var pagesScanned = 0
        batch: while true {
            let startStatus = api.start(h)
            if startStatus == SANE_STATUS_NO_DOCS { break batch }
            if startStatus == SANE_STATUS_CANCELLED { throw ScanError.cancelled }
            guard startStatus == SANE_STATUS_GOOD else {
                throw failure(api, "sane_start", startStatus)
            }

            var params = SANE_Parameters()
            _ = api.getParameters(h, &params)
            let expectedBytes = params.lines > 0
                ? Int(params.bytes_per_line) * Int(params.lines)
                : 0

            var data = Data()
            data.reserveCapacity(max(expectedBytes, 1 << 20))
            let bufferLength = 256 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferLength)

            reading: while true {
                var got: SANE_Int = 0
                let readStatus = buffer.withUnsafeMutableBufferPointer {
                    api.read(h, $0.baseAddress, SANE_Int(bufferLength), &got)
                }
                if readStatus == SANE_STATUS_EOF { break reading }
                if readStatus == SANE_STATUS_CANCELLED { throw ScanError.cancelled }
                guard readStatus == SANE_STATUS_GOOD else {
                    throw failure(api, "sane_read", readStatus)
                }
                if got > 0 {
                    buffer.withUnsafeBufferPointer {
                        data.append($0.baseAddress!, count: Int(got))
                    }
                    if expectedBytes > 0 {
                        onProgress?(pagesScanned + 1, min(1.0, Double(data.count) / Double(expectedBytes)))
                    }
                }
            }

            guard let image = ImageBuilder.makeImage(params: params, data: data) else {
                throw ScanError.imageDecodeFailed
            }
            pagesScanned += 1
            onPage(ScannedPage(image: image, dpi: settings.resolution, index: pagesScanned))
        }

        api.cancel(h)
        return pagesScanned
    }

    /// Safe to call from any thread while a scan is running.
    public func cancelScan() {
        stateLock.lock(); let handle = currentHandle; stateLock.unlock()
        if let handle = handle, let api = api {
            api.cancel(handle)
        }
    }

    // MARK: - Options

    private func optionIndex(_ h: UnsafeMutableRawPointer, api: SaneAPI) throws -> [String: SANE_Int] {
        var count: SANE_Int = 0
        let status = api.controlOption(h, 0, SANE_ACTION_GET_VALUE, &count, nil)
        guard status == SANE_STATUS_GOOD, count > 0 else {
            throw failure(api, "sane_control_option(count)", status)
        }
        var map: [String: SANE_Int] = [:]
        for i in 1..<count {
            guard let descriptor = api.getOptionDescriptor(h, i) else { continue }
            let d = descriptor.pointee
            guard d.type != SANE_TYPE_GROUP, let cName = d.name else { continue }
            let name = String(cString: cName)
            if !name.isEmpty { map[name] = i }
        }
        return map
    }

    private func configure(_ h: UnsafeMutableRawPointer, api: SaneAPI, settings: ScanSettings) throws {
        var options = try optionIndex(h, api: api)
        let reloadFlag: SANE_Int = 2  // SANE_INFO_RELOAD_OPTIONS

        // Absent options are skipped silently: the backend decides what the
        // hardware supports, and every set below is an optimization, not a must.
        func set(_ name: String, _ write: (SANE_Int) -> SANE_Status, valueDescription: String) throws {
            guard let index = options[name] else { return }
            let status = write(index)
            guard status == SANE_STATUS_GOOD else {
                throw failure(api, "set \(name)=\(valueDescription)", status)
            }
        }

        func setString(_ name: String, _ value: String) throws {
            try set(name, { index in
                var info: SANE_Int = 0
                var chars = Array(value.utf8CString)
                let status = chars.withUnsafeMutableBufferPointer {
                    api.controlOption(h, index, SANE_ACTION_SET_VALUE, $0.baseAddress, &info)
                }
                if info & reloadFlag != 0, let refreshed = try? optionIndex(h, api: api) {
                    options = refreshed
                }
                return status
            }, valueDescription: value)
        }

        func setWord(_ name: String, _ word: SANE_Int) throws {
            try set(name, { index in
                var info: SANE_Int = 0
                var value = word
                let status = api.controlOption(h, index, SANE_ACTION_SET_VALUE, &value, &info)
                if info & reloadFlag != 0, let refreshed = try? optionIndex(h, api: api) {
                    options = refreshed
                }
                return status
            }, valueDescription: "\(word)")
        }

        func setFixed(_ name: String, _ value: Double) throws {
            try setWord(name, SANE_Int((value * 65536.0).rounded()))
        }

        try setString("source", settings.duplex ? "ADF Duplex" : "ADF Front")
        try setString("mode", settings.mode.rawValue)
        try setWord("resolution", SANE_Int(settings.resolution))

        let paper = settings.paperSize.mm
        try setFixed("page-width", paper.width)
        try setFixed("page-height", paper.height)
        try setFixed("tl-x", 0)
        try setFixed("tl-y", 0)
        try setFixed("br-x", paper.width)
        try setFixed("br-y", paper.height)

        if settings.deskew {
            try setWord("swdeskew", 1)
        }
        if settings.skipBlankPages {
            // Pages that are >= ~10% covered survive; near-empty backsides are dropped.
            try setFixed("swskip", 10.0)
        }
    }

    private func failure(_ api: SaneAPI, _ operation: String, _ status: SANE_Status) -> ScanError {
        .saneFailure(operation: operation, status: api.statusText(status), code: Int32(status.rawValue))
    }
}
